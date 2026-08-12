import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../accounts/domain/work_platform.dart';
import '../../shifts/domain/shift.dart';
import '../domain/driver_location.dart';
import '../domain/driving_session.dart';
import 'location_tracker.dart';

/// Why a start attempt failed, so the UI can say something specific.
enum StartFailure { serviceDisabled, permissionDenied, permissionDeniedForever }

class StartResult {
  const StartResult.started() : failure = null;
  const StartResult.failed(this.failure);

  final StartFailure? failure;

  bool get isStarted => failure == null;
}

/// Owns the live driving session: timing, mileage accumulation and the
/// persistence that lets a session survive the app being suspended or killed.
class DrivingSessionController extends ChangeNotifier {
  DrivingSessionController({
    required LocationTracker tracker,
    required Future<void> Function(DrivingSession? session) persist,
    DrivingSession? restored,
    DateTime Function()? clock,
  }) {
    _tracker = tracker;
    _persist = persist;
    _clock = clock ?? DateTime.now;
    _session = restored;
    if (restored != null) {
      // Carry the already-banked mileage forward so a resumed session keeps
      // counting from where it left off rather than restarting at zero.
      _accumulator = DistanceAccumulator(
        initialMeters: restored.distanceMeters,
      );
    }
  }

  late final LocationTracker _tracker;
  late final Future<void> Function(DrivingSession? session) _persist;

  /// Wall clock, injectable because elapsed time is the whole point of a
  /// session and `DateTime.now()` cannot be advanced from a widget test.
  late final DateTime Function() _clock;

  DrivingSession? _session;
  DistanceAccumulator _accumulator = DistanceAccumulator();
  StreamSubscription<DriverLocation>? _subscription;

  /// True when the OS granted only foreground location, which means mileage
  /// may stop accruing once the driver switches to Uber. Surfaced rather than
  /// hidden, because silently under-counting miles overstates profit.
  bool _backgroundLimited = false;

  DrivingSession? get session => _session;
  bool get isDriving => _session?.isActive ?? false;
  bool get backgroundLimited => _backgroundLimited;
  double get trackedMiles => _session?.miles ?? 0;

  /// Resumes a session that was already running when the app was last alive.
  ///
  /// Mileage recorded while the process was dead is unrecoverable, but the
  /// elapsed time is not: it comes from the stored start timestamp.
  Future<void> resumeIfActive() async {
    final restored = _session;
    if (restored == null || !restored.isActive) return;
    final permission = await _tracker.checkPermission();
    _backgroundLimited = permission == LocationPermissionState.whileInUse;
    if (permission == LocationPermissionState.always ||
        permission == LocationPermissionState.whileInUse) {
      await _listen();
    }
    notifyListeners();
  }

  /// Whether the driver still has to be asked for location at all.
  ///
  /// Used to decide if the disclosure needs showing: a driver who already
  /// granted access should not be made to read it again.
  Future<bool> needsPermissionRequest() async {
    final permission = await _tracker.checkPermission();
    return permission != LocationPermissionState.always;
  }

  /// Escalates foreground access to background access mid-shift.
  ///
  /// Returns true once the platform reports *always*. Anything else leaves the
  /// warning in place rather than claiming success the OS did not grant.
  Future<bool> upgradeToBackgroundTracking() async {
    final permission = await _tracker.requestAlwaysPermission();
    final granted = permission == LocationPermissionState.always;
    _backgroundLimited = !granted && isDriving;
    notifyListeners();
    return granted;
  }

  Future<StartResult> start({
    required WorkPlatform platform,
    required double vehicleCostPerMile,
    DateTime? now,
  }) async {
    if (isDriving) return const StartResult.started();

    final permission = await _tracker.requestPermission();
    switch (permission) {
      case LocationPermissionState.serviceDisabled:
        return const StartResult.failed(StartFailure.serviceDisabled);
      case LocationPermissionState.deniedForever:
        return const StartResult.failed(StartFailure.permissionDeniedForever);
      case LocationPermissionState.denied:
        return const StartResult.failed(StartFailure.permissionDenied);
      case LocationPermissionState.whileInUse:
        _backgroundLimited = true;
      case LocationPermissionState.always:
        _backgroundLimited = false;
    }

    final startedAt = now ?? _clock();
    _accumulator = DistanceAccumulator();
    _session = DrivingSession(
      id: 'session-${startedAt.microsecondsSinceEpoch}',
      startedAt: startedAt,
      platform: platform,
      vehicleCostPerMile: vehicleCostPerMile,
    );
    await _persist(_session);
    await _listen();
    notifyListeners();
    return const StartResult.started();
  }

  /// Ends the session and hands back the shift the earnings then attach to.
  Future<Shift?> end({DateTime? now}) async {
    final active = _session;
    if (active == null || !active.isActive) return null;

    // The figures are taken first, then tracking is torn down in the
    // background. Awaiting teardown here would make finishing a shift wait on
    // platform stream cleanup that nothing downstream depends on.
    final endedAt = now ?? _clock();
    final finished = active.copyWith(
      endedAt: endedAt,
      distanceMeters: _accumulator.meters,
    );
    _session = null;
    _backgroundLimited = false;
    unawaited(_stopTracking());
    await _persist(null);
    notifyListeners();
    return finished.toDraftShift(endedAt: endedAt);
  }

  /// Abandons a session without producing a shift.
  Future<void> discard() async {
    _session = null;
    _backgroundLimited = false;
    unawaited(_stopTracking());
    await _persist(null);
    notifyListeners();
  }

  /// Detaches from the location stream. Safe to leave in flight: [_onLocation]
  /// ignores any fix that arrives once the session is gone.
  Future<void> _stopTracking() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _tracker.stop();
  }

  Future<void> _listen() async {
    await _subscription?.cancel();
    await _tracker.start();
    _subscription = _tracker.locations.listen(_onLocation, onError: (_) {});
  }

  void _onLocation(DriverLocation location) {
    if (!_accumulator.add(location)) return;
    final active = _session;
    if (active == null) return;
    _session = active.copyWith(distanceMeters: _accumulator.meters);
    // Persisted on every counted leg so a kill loses at most the current leg
    // rather than the whole shift's mileage.
    unawaited(_persist(_session));
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _tracker.stop();
    super.dispose();
  }
}
