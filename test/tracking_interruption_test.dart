import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/driving/application/driving_session_controller.dart';
import 'package:driver_wealth_os/features/driving/application/location_tracker.dart';
import 'package:driver_wealth_os/features/driving/domain/driver_location.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_location_tracker.dart';

/// A session that looks live while banking no miles is the worst failure this
/// app has: fewer miles means a smaller vehicle-cost deduction, so the profit
/// figure is wrong in the flattering direction. These tests exist to make sure
/// the driver is told instead.
void main() {
  DrivingSessionController controllerFor(FakeLocationTracker tracker) =>
      DrivingSessionController(tracker: tracker, persist: (_) async {});

  Future<StartResult> startShift(DrivingSessionController controller) =>
      controller.start(platform: WorkPlatform.uber, vehicleCostPerMile: 0.30);

  test('a stream failure mid-shift is reported, not swallowed', () async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final controller = controllerFor(tracker);

    await startShift(controller);
    expect(controller.trackingInterrupted, isFalse);

    tracker.emitError(Exception('location provider died'));
    await Future<void>.microtask(() {});

    expect(controller.trackingInterrupted, isTrue);
    // The shift itself survives — time is still accruing from the timestamp.
    expect(controller.isDriving, isTrue);
  });

  test('a later fix clears the interruption', () async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final controller = controllerFor(tracker);

    await startShift(controller);
    tracker.emitError(Exception('dropped'));
    await Future<void>.microtask(() {});
    expect(controller.trackingInterrupted, isTrue);

    await tracker.emit(
      DriverLocation(
        latitude: 37.0,
        longitude: -122.0,
        timestamp: DateTime.now(),
      ),
    );

    // Any fix proves the provider is alive, even the first one, which the
    // accumulator has no previous point to measure against.
    expect(controller.trackingInterrupted, isFalse);
  });

  test('failing to attach to the stream is reported like a failure', () async {
    final tracker = FakeLocationTracker()..startError = Exception('no service');
    addTearDown(tracker.dispose);
    final controller = controllerFor(tracker);

    final result = await startShift(controller);

    // The session starts — the driver's time should still be counted — but the
    // app does not pretend mileage is being measured.
    expect(result.isStarted, isTrue);
    expect(controller.trackingInterrupted, isTrue);
  });

  test('permission revoked while backgrounded is caught on resume', () async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final controller = controllerFor(tracker);

    await startShift(controller);
    expect(controller.trackingInterrupted, isFalse);

    // The driver turns location off in Settings. Nothing calls back.
    tracker.permission = LocationPermissionState.denied;
    await controller.refreshAfterResume();

    expect(controller.trackingInterrupted, isTrue);
    expect(controller.isDriving, isTrue);
  });

  test('resume re-reads a downgrade to foreground-only', () async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final controller = controllerFor(tracker);

    await startShift(controller);
    expect(controller.backgroundLimited, isFalse);

    tracker.permission = LocationPermissionState.whileInUse;
    await controller.refreshAfterResume();

    // Stale in the reassuring direction is exactly what must not happen.
    expect(controller.backgroundLimited, isTrue);
    expect(controller.trackingInterrupted, isFalse);
  });

  test('resume does nothing when no shift is running', () async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final controller = controllerFor(tracker);

    await controller.refreshAfterResume();

    expect(controller.isDriving, isFalse);
    expect(controller.trackingInterrupted, isFalse);
    expect(tracker.started, isFalse);
  });

  test('starting a shift asks for the notification permission', () async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final controller = controllerFor(tracker);

    await startShift(controller);

    // Android 13+ will not show the foreground-service notification without it.
    expect(tracker.notificationPermissionRequested, isTrue);
  });

  test('ending a shift clears the interruption', () async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final controller = controllerFor(tracker);

    await startShift(controller);
    tracker.emitError(Exception('dropped'));
    await Future<void>.microtask(() {});

    await controller.end();

    expect(controller.trackingInterrupted, isFalse);
  });
}
