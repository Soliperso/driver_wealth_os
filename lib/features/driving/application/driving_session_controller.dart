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
    void Function(Shift draft)? onAutoEnded,
  }) {
    _tracker = tracker;
    _persist = persist;
    _clock = clock ?? DateTime.now;
    _onAutoEnded = onAutoEnded;
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

  /// Where a self-ended shift goes.
  ///
  /// [endIfPauseExpired] can fire during start-up, long before any screen is
  /// watching, so the draft is banked here rather than left for a caller that
  /// may not exist. Losing it would mean losing a whole shift's hours.
  late final void Function(Shift draft)? _onAutoEnded;

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

  /// True when the location stream has failed mid-shift.
  ///
  /// A dead provider produces a session that looks live and accrues no miles,
  /// which shrinks the vehicle cost and overstates profit — the one direction
  /// this app must never be wrong in. Cleared by the next accepted fix.
  bool _trackingInterrupted = false;

  DrivingSession? get session => _session;
  bool get isDriving => _session?.isActive ?? false;

  /// A paused session is still active — it is on a break, not finished — so
  /// this is deliberately not folded into [isDriving].
  bool get isPaused => _session?.isPaused ?? false;
  bool get backgroundLimited => _backgroundLimited;
  bool get trackingInterrupted => _trackingInterrupted;
  double get trackedMiles => _session?.miles ?? 0;

  /// Resumes a session that was already running when the app was last alive.
  ///
  /// Mileage recorded while the process was dead is unrecoverable, but the
  /// elapsed time is not: it comes from the stored start timestamp.
  Future<void> resumeIfActive() async {
    final restored = _session;
    if (restored == null || !restored.isActive) return;
    // A break that outlived the app is the case this guards: the session is
    // closed out at its limit rather than silently resumed hours later.
    if (await endIfPauseExpired() != null) return;
    // Still on a break, so nothing should start counting until the driver
    // says so.
    if (isPaused) {
      notifyListeners();
      return;
    }
    final permission = await _tracker.checkPermission();
    _backgroundLimited = permission == LocationPermissionState.whileInUse;
    if (permission == LocationPermissionState.always ||
        permission == LocationPermissionState.whileInUse) {
      await _listen();
    }
    notifyListeners();
  }

  /// Re-checks the things the OS can change while the app is backgrounded.
  ///
  /// Permission can be revoked or downgraded in Settings mid-shift, and a
  /// suspended app can come back with its location subscription dropped.
  /// Neither produces a callback, so the state is re-read on resume rather
  /// than trusted from whenever the shift happened to start.
  Future<void> refreshAfterResume() async {
    if (!isDriving) return;
    // The common way a pause overruns: paused, app closed, reopened much
    // later. Checked before anything else, because a session past the limit
    // should not be having its permissions refreshed at all.
    if (await endIfPauseExpired() != null) return;
    // Tracking is meant to be off during a break, so there is nothing to
    // re-check and nothing to reattach.
    if (isPaused) return;
    final permission = await _tracker.checkPermission();
    final usable =
        permission == LocationPermissionState.always ||
        permission == LocationPermissionState.whileInUse;
    _backgroundLimited = permission == LocationPermissionState.whileInUse;
    if (!usable) {
      // Revoked mid-shift. The session keeps its banked miles and elapsed
      // time, but the driver has to be told it is no longer counting.
      _trackingInterrupted = true;
      notifyListeners();
      return;
    }
    if (_subscription == null) await _listen();
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

  /// Starts a session running [platforms], which is more than one whenever the
  /// driver is multi-apping.
  Future<StartResult> start({
    required Set<WorkPlatform> platforms,
    required double vehicleCostPerMile,
    DateTime? now,
  }) async {
    assert(platforms.isNotEmpty, 'A session must start on at least one app');
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

    // Asked only once location is granted and a shift is actually starting,
    // so the driver sees it in the context that explains it. A refusal is not
    // fatal, so the result is not checked.
    await _tracker.requestNotificationPermission();

    final startedAt = now ?? _clock();
    _accumulator = DistanceAccumulator();
    _session = DrivingSession(
      id: 'session-${startedAt.microsecondsSinceEpoch}',
      startedAt: startedAt,
      platformSpans: [
        for (final platform in platforms)
          PlatformSpan(platform: platform, from: startedAt),
      ],
      vehicleCostPerMile: vehicleCostPerMile,
    );
    await _persist(_session);
    await _listen();
    notifyListeners();
    return const StartResult.started();
  }

  /// Switches another app on without interrupting the shift.
  ///
  /// Deliberately touches nothing but the spans. Time, mileage and the break
  /// bookkeeping are properties of the car, not of which apps are open, so
  /// turning Lyft on halfway through an Uber shift must not disturb any of
  /// them. Returns false when nothing changed.
  Future<bool> addPlatform(WorkPlatform platform, {DateTime? now}) async {
    final active = _session;
    if (active == null || !active.isActive) return false;
    final next = active.addingPlatform(platform, at: now ?? _clock());
    if (identical(next, active)) return false;
    _session = next;
    await _persist(_session);
    notifyListeners();
    return true;
  }

  /// Switches an app off, leaving the shift running on whatever else is live.
  ///
  /// Refused when it would leave the session running nothing — see
  /// [DrivingSession.removingPlatform]. Returns false in that case, so the UI
  /// can leave the last chip looking un-removable rather than silently doing
  /// nothing.
  Future<bool> removePlatform(WorkPlatform platform, {DateTime? now}) async {
    final active = _session;
    if (active == null || !active.isActive) return false;
    final next = active.removingPlatform(platform, at: now ?? _clock());
    if (identical(next, active)) return false;
    _session = next;
    await _persist(_session);
    notifyListeners();
    return true;
  }

  /// Starts a break: the clock stops counting and location tracking detaches.
  ///
  /// Both stop together on purpose. Leaving GPS running through a lunch break
  /// would drain the battery for nothing, and stopping the clock while still
  /// banking miles would produce a shift whose cost per hour is nonsense.
  Future<void> pause({DateTime? now}) async {
    final active = _session;
    if (active == null || !active.isActive || active.isPaused) return;

    _session = active.copyWith(pausedAt: now ?? _clock());
    // Neither warning means anything while tracking is off by choice, and a
    // red "mileage stopped" alarm for a break the driver asked for would
    // teach them to ignore it when it matters.
    _backgroundLimited = false;
    _trackingInterrupted = false;
    await _persist(_session);
    // The break is on screen before the platform teardown is waited on, so
    // tapping pause feels immediate. The teardown is still part of this
    // future, unlike the fire-and-forget one in [end] — a caller that wants to
    // know location collection has actually stopped can await it.
    notifyListeners();
    await _stopTracking();
  }

  /// Ends the break and starts counting again.
  Future<void> resume({DateTime? now}) async {
    final active = _session;
    final pausedAt = active?.pausedAt;
    if (active == null || !active.isActive || pausedAt == null) return;

    final taken = (now ?? _clock()).difference(pausedAt).inMilliseconds;
    _session = active.copyWith(
      clearPausedAt: true,
      pausedMillis: active.pausedMillis + (taken < 0 ? 0 : taken),
    );
    // The driver may be somewhere else entirely by now. Without this the
    // first fix would be measured from where the break started.
    _accumulator.reanchor();
    await _persist(_session);
    // Reattaching can fail or find permission revoked during the break;
    // _listen already reports both.
    await _listen();
    notifyListeners();
  }

  /// Ends a session that has sat paused past [pauseAutoEndAfter].
  ///
  /// Returns the draft shift when it fired, null otherwise. Idempotent, so it
  /// is safe to call from a display ticker.
  ///
  /// The shift is cut off at the moment the limit was reached rather than at
  /// whenever the app noticed, so reopening the app days later still produces
  /// the same figures.
  Future<Shift?> endIfPauseExpired({DateTime? now}) async {
    final active = _session;
    final pausedAt = active?.pausedAt;
    if (active == null || !active.isActive || pausedAt == null) return null;
    if ((now ?? _clock()).difference(pausedAt) < pauseAutoEndAfter) return null;
    final draft = await end(now: pausedAt.add(pauseAutoEndAfter));
    if (draft != null) _onAutoEnded?.call(draft);
    return draft;
  }

  /// Ends the session and hands back the shift the earnings then attach to.
  Future<Shift?> end({DateTime? now}) async {
    final active = _session;
    if (active == null || !active.isActive) return null;

    // The figures are taken first, then tracking is torn down in the
    // background. Awaiting teardown here would make finishing a shift wait on
    // platform stream cleanup that nothing downstream depends on.
    final endedAt = now ?? _clock();
    final finished = active
        .copyWith(endedAt: endedAt, distanceMeters: _accumulator.meters)
        // Ending the shift switches every app off, so no span is left claiming
        // it is still running after the session is over.
        .closingSpans(at: endedAt);
    _session = null;
    _backgroundLimited = false;
    _trackingInterrupted = false;
    unawaited(_stopTracking());
    await _persist(null);
    notifyListeners();
    return finished.toDraftShift(endedAt: endedAt);
  }

  /// Abandons a session without producing a shift.
  Future<void> discard() async {
    _session = null;
    _backgroundLimited = false;
    _trackingInterrupted = false;
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
    try {
      await _tracker.start();
    } catch (_) {
      // Failing to attach is the same problem as the stream dying later: the
      // session would sit there banking nothing.
      _trackingInterrupted = true;
      notifyListeners();
      return;
    }
    _trackingInterrupted = false;
    _subscription = _tracker.locations.listen(
      _onLocation,
      onError: (Object _) {
        if (_session == null) return;
        _trackingInterrupted = true;
        notifyListeners();
      },
    );
  }

  void _onLocation(DriverLocation location) {
    // Any fix at all proves the provider is alive, even one the accumulator
    // rejects as drift.
    if (_trackingInterrupted) {
      _trackingInterrupted = false;
      notifyListeners();
    }
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
