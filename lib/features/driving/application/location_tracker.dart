import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/driver_location.dart'
    show DriverLocation, DistanceAccumulator;

enum LocationPermissionState {
  /// Cleared for background updates — tracking survives the driver switching
  /// to the Uber app.
  always,

  /// Usable, but the OS may stop updates once the app leaves the foreground.
  whileInUse,

  denied,

  /// Denied permanently; only a trip to system settings can change it.
  deniedForever,

  /// Device location is switched off entirely.
  serviceDisabled,
}

/// Our seam over Core Location and Android's fused provider.
///
/// Everything above this interface deals in [DriverLocation] and knows nothing
/// about the plugin, which keeps the session logic testable without a device.
abstract interface class LocationTracker {
  Future<LocationPermissionState> checkPermission();

  Future<LocationPermissionState> requestPermission();

  /// Asks the platform to escalate foreground access to background access.
  ///
  /// Deliberately separate from [requestPermission] because neither OS grants
  /// background location in one step:
  /// - iOS shows *When In Use* first and only offers *Always* on a later,
  ///   separate prompt.
  /// - Android 10+ requires `ACCESS_BACKGROUND_LOCATION` to be requested after
  ///   foreground access has already been granted.
  ///
  /// The OS decides whether a prompt actually appears — it may silently return
  /// the current state, or send the driver to Settings instead. The result is
  /// whatever the platform reports afterwards, not a promise of success.
  Future<LocationPermissionState> requestAlwaysPermission();

  /// Asks for the notification permission the foreground-service notification
  /// needs on Android 13+.
  ///
  /// Separate from location because it is not a location grant and a refusal
  /// is not fatal: tracking still runs, the driver just loses the persistent
  /// indicator. Nothing should block a shift on the answer.
  Future<void> requestNotificationPermission();

  Stream<DriverLocation> get locations;

  Future<void> start();

  Future<void> stop();
}

final class GeolocatorLocationTracker implements LocationTracker {
  GeolocatorLocationTracker();

  StreamSubscription<Position>? _subscription;
  final _controller = StreamController<DriverLocation>.broadcast();

  @override
  Stream<DriverLocation> get locations => _controller.stream;

  @override
  Future<LocationPermissionState> checkPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.serviceDisabled;
    }
    return _map(await Geolocator.checkPermission());
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return _map(permission);
  }

  @override
  Future<LocationPermissionState> requestAlwaysPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.serviceDisabled;
    }
    final current = await Geolocator.checkPermission();
    if (current == LocationPermission.always) {
      return LocationPermissionState.always;
    }
    // Only meaningful once foreground access exists; asking before that just
    // re-runs the first prompt.
    if (current != LocationPermission.whileInUse) {
      return _map(current);
    }
    return _map(await Geolocator.requestPermission());
  }

  @override
  Future<void> requestNotificationPermission() async {
    // Only Android 13+ gates the foreground-service notification behind a
    // runtime grant. Geolocator cannot request it, and without it the
    // notification it configures is never shown.
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (status.isDenied) await Permission.notification.request();
  }

  /// Opens the OS settings page for this app.
  ///
  /// The escape hatch for a driver who has permanently denied location, or
  /// whose platform will not re-prompt for *Always* — in both cases the app
  /// cannot fix it and Settings is the only route.
  static Future<void> openSettings() => Geolocator.openAppSettings();

  @override
  Future<void> start() async {
    await _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(
          (position) => _controller.add(
            DriverLocation(
              latitude: position.latitude,
              longitude: position.longitude,
              timestamp: position.timestamp,
              accuracyMeters: position.accuracy,
              speedMetersPerSecond: position.speed,
            ),
          ),
          onError: _controller.addError,
        );
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// A 20 m displacement filter keeps the fix rate sane without losing real
  /// movement.
  ///
  /// It must stay *above* [DistanceAccumulator.minLegMeters], or every emitted
  /// fix falls into a dead zone between the platform filter and our own floor
  /// and gets discarded — which would quietly under-count miles in exactly the
  /// stop-and-go traffic rideshare drivers spend their day in.
  LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        // Android will not deliver reliable background updates without a
        // visible foreground service, and the driver is entitled to see that
        // tracking is running.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Driving session active',
          notificationText: 'Keeprate is tracking time and mileage.',
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        // Required for Core Location to keep delivering fixes once the driver
        // switches to the Uber app.
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        activityType: ActivityType.automotiveNavigation,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    );
  }

  static LocationPermissionState _map(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always => LocationPermissionState.always,
        LocationPermission.whileInUse => LocationPermissionState.whileInUse,
        LocationPermission.deniedForever =>
          LocationPermissionState.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => LocationPermissionState.denied,
      };
}
