import 'dart:async';

import 'package:driver_wealth_os/features/driving/application/location_tracker.dart';
import 'package:driver_wealth_os/features/driving/domain/driver_location.dart';

/// Feeds scripted GPS fixes so session behaviour can be tested without a
/// device, a real satellite fix, or a permission dialog.
class FakeLocationTracker implements LocationTracker {
  FakeLocationTracker({
    this.permission = LocationPermissionState.always,
    this.permissionAfterUpgrade,
  });

  LocationPermissionState permission;

  /// What the platform reports once escalation is attempted. Null means the OS
  /// declined to change anything, which is a real outcome on both platforms.
  LocationPermissionState? permissionAfterUpgrade;

  final _controller = StreamController<DriverLocation>.broadcast();

  var started = false;
  var stopped = false;
  var upgradeRequested = false;
  var notificationPermissionRequested = false;

  /// When set, [start] throws instead of attaching — the platform refusing to
  /// deliver a location stream at all.
  Object? startError;

  @override
  Stream<DriverLocation> get locations => _controller.stream;

  @override
  Future<LocationPermissionState> checkPermission() async => permission;

  @override
  Future<LocationPermissionState> requestPermission() async => permission;

  @override
  Future<LocationPermissionState> requestAlwaysPermission() async {
    upgradeRequested = true;
    final upgraded = permissionAfterUpgrade;
    if (upgraded != null) permission = upgraded;
    return permission;
  }

  @override
  Future<void> requestNotificationPermission() async {
    notificationPermissionRequested = true;
  }

  @override
  Future<void> start() async {
    final error = startError;
    if (error != null) throw error;
    started = true;
    stopped = false;
  }

  /// Simulates the platform stream failing mid-shift, which is what a revoked
  /// permission or a dead provider looks like from here.
  void emitError(Object error) => _controller.addError(error);

  @override
  Future<void> stop() async {
    stopped = true;
  }

  /// Emits a fix and yields so the controller's listener runs before the test
  /// asserts on the result.
  ///
  /// Yields via a microtask rather than `Future.delayed`. A zero-duration delay
  /// is still a *timer*, and inside `testWidgets` timers only fire when the
  /// test pumps — so awaiting one here would deadlock the test body before it
  /// ever got the chance to pump.
  Future<void> emit(DriverLocation location) async {
    _controller.add(location);
    await Future<void>.microtask(() {});
  }

  Future<void> dispose() => _controller.close();
}
