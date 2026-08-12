import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/driving/application/driving_session_controller.dart';
import 'package:driver_wealth_os/features/driving/application/location_tracker.dart';
import 'package:driver_wealth_os/features/driving/domain/driver_location.dart';
import 'package:driver_wealth_os/features/driving/domain/driving_session.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_location_tracker.dart';

/// Roughly 111 m per 0.001 degrees of latitude, which makes the expected
/// distances in these tests easy to reason about.
DriverLocation at(
  double lat,
  double lon,
  DateTime time, {
  double accuracy = 5,
}) => DriverLocation(
  latitude: lat,
  longitude: lon,
  timestamp: time,
  accuracyMeters: accuracy,
);

void main() {
  group('distance accumulation', () {
    final t0 = DateTime(2026, 8, 11, 6);

    test('sums consecutive legs', () {
      final accumulator = DistanceAccumulator();
      accumulator.add(at(37.0000, -122.0, t0));
      accumulator.add(at(37.0100, -122.0, t0.add(const Duration(minutes: 1))));
      accumulator.add(at(37.0200, -122.0, t0.add(const Duration(minutes: 2))));

      // ~1.11 km per 0.01 degrees, twice.
      expect(accumulator.meters, closeTo(2224, 20));
      expect(accumulator.miles, closeTo(1.38, .05));
    });

    test('a phone sitting still does not invent mileage', () {
      final accumulator = DistanceAccumulator();
      var time = t0;
      accumulator.add(at(37.0, -122.0, time));

      // Twenty minutes of typical stationary GPS wander at an airport queue.
      for (var i = 0; i < 40; i++) {
        time = time.add(const Duration(seconds: 30));
        final jitter = (i.isEven ? 1 : -1) * 0.00004; // ~4.4 m
        accumulator.add(at(37.0 + jitter, -122.0 + jitter, time));
      }

      // The whole point: drift must not become billable miles, because miles
      // become a vehicle cost and a wrong profit figure.
      expect(accumulator.meters, 0);
    });

    test('counts a slow crawl through traffic', () {
      // The regression this guards: the platform emits a fix every ~20 m, and
      // an accumulator floor above that would discard every one of them. An
      // hour of gridlock would bank no miles, shrinking the vehicle cost and
      // making reported profit too high.
      final accumulator = DistanceAccumulator();
      var time = t0;
      var lat = 37.0;
      accumulator.add(at(lat, -122.0, time));

      // 30 legs of ~22 m, ten seconds apart — about 5 mph.
      for (var i = 0; i < 30; i++) {
        time = time.add(const Duration(seconds: 10));
        lat += 0.0002;
        accumulator.add(at(lat, -122.0, time));
      }

      expect(accumulator.meters, closeTo(666, 40));
    });

    test('counts short legs when the device reports driving speed', () {
      final accumulator = DistanceAccumulator();
      accumulator.add(at(37.0, -122.0, t0));
      accumulator.add(
        DriverLocation(
          latitude: 37.0001, // ~11 m
          longitude: -122.0,
          timestamp: t0.add(const Duration(seconds: 4)),
          accuracyMeters: 5,
          speedMetersPerSecond: 6,
        ),
      );

      expect(accumulator.meters, greaterThan(9));
    });

    test('ignores fixes too inaccurate to trust', () {
      final accumulator = DistanceAccumulator();
      accumulator.add(at(37.0, -122.0, t0));
      accumulator.add(
        at(37.02, -122.0, t0.add(const Duration(minutes: 1)), accuracy: 300),
      );

      expect(accumulator.meters, 0);
    });

    test('re-anchors on an implausible jump instead of crediting it', () {
      final accumulator = DistanceAccumulator();
      accumulator.add(at(37.0, -122.0, t0));
      // 55 km in one minute is not a car.
      accumulator.add(at(37.5, -122.0, t0.add(const Duration(minutes: 1))));

      expect(accumulator.meters, 0);

      // Movement after the jump is measured from the new anchor.
      accumulator.add(at(37.51, -122.0, t0.add(const Duration(minutes: 3))));
      expect(accumulator.meters, closeTo(1112, 30));
    });
  });

  group('session timing', () {
    test('elapsed time is derived from timestamps, not a counter', () {
      final startedAt = DateTime(2026, 8, 11, 6, 2);
      final session = DrivingSession(
        id: 's1',
        startedAt: startedAt,
        platform: WorkPlatform.uber,
      );

      // Simulates the app having been suspended for hours: nothing was
      // incrementing, yet the elapsed time is still correct.
      final now = startedAt.add(const Duration(hours: 5, minutes: 15));
      expect(session.elapsed(now: now), const Duration(hours: 5, minutes: 15));
      expect(formatElapsed(session.elapsed(now: now)), '05:15:00');
    });

    test('a finished session yields a shift with tracked time and miles', () {
      final startedAt = DateTime(2026, 8, 11, 6, 2);
      final endedAt = startedAt.add(const Duration(hours: 5, minutes: 15));
      final session = DrivingSession(
        id: 's1',
        startedAt: startedAt,
        platform: WorkPlatform.uber,
        distanceMeters: 221764, // ~137.8 miles
        vehicleCostPerMile: .30,
      );

      final shift = session.toDraftShift(endedAt: endedAt);

      expect(shift.hours, closeTo(5.25, .001));
      expect(shift.miles, closeTo(137.8, .1));
      expect(shift.source, ShiftSource.tracked);
      // A session knows what was driven, never what was paid.
      expect(shift.gross, 0);
      expect(shift.directExpenses, 0);
    });
  });

  group('session controller', () {
    late FakeLocationTracker tracker;
    late List<DrivingSession?> persisted;

    DrivingSessionController build({DrivingSession? restored}) =>
        DrivingSessionController(
          tracker: tracker,
          restored: restored,
          persist: (session) async => persisted.add(session),
        );

    setUp(() {
      tracker = FakeLocationTracker();
      persisted = [];
    });

    tearDown(() => tracker.dispose());

    test('start refuses without permission and explains why', () async {
      tracker.permission = LocationPermissionState.deniedForever;
      final controller = build();

      final result = await controller.start(
        platform: WorkPlatform.uber,
        vehicleCostPerMile: .30,
      );

      expect(result.isStarted, isFalse);
      expect(result.failure, StartFailure.permissionDeniedForever);
      expect(controller.isDriving, isFalse);
      expect(tracker.started, isFalse);
    });

    test('start flags foreground-only permission', () async {
      tracker.permission = LocationPermissionState.whileInUse;
      final controller = build();

      await controller.start(
        platform: WorkPlatform.uber,
        vehicleCostPerMile: .30,
      );

      // Under-counting miles overstates profit, so the limitation is surfaced.
      expect(controller.backgroundLimited, isTrue);
    });

    test('accumulates mileage and persists on each counted leg', () async {
      final controller = build();
      final t0 = DateTime(2026, 8, 11, 6);
      await controller.start(
        platform: WorkPlatform.uber,
        vehicleCostPerMile: .30,
        now: t0,
      );

      await tracker.emit(at(37.0, -122.0, t0));
      await tracker.emit(at(37.01, -122.0, t0.add(const Duration(minutes: 1))));

      expect(controller.trackedMiles, closeTo(.69, .05));
      // The start plus at least one mileage update, so a kill loses one leg
      // rather than the whole shift.
      expect(persisted.length, greaterThanOrEqualTo(2));
      expect(persisted.last?.distanceMeters, greaterThan(0));
    });

    test('end produces a draft shift and clears the stored session', () async {
      final controller = build();
      final t0 = DateTime(2026, 8, 11, 6);
      await controller.start(
        platform: WorkPlatform.lyft,
        vehicleCostPerMile: .30,
        now: t0,
      );
      await tracker.emit(at(37.0, -122.0, t0));
      await tracker.emit(at(37.02, -122.0, t0.add(const Duration(minutes: 2))));

      final draft = await controller.end(now: t0.add(const Duration(hours: 3)));

      expect(draft, isNotNull);
      expect(draft!.hours, closeTo(3, .001));
      expect(draft.miles, greaterThan(1));
      expect(draft.platform, WorkPlatform.lyft);
      expect(controller.isDriving, isFalse);
      expect(tracker.stopped, isTrue);
      // Null persisted last: nothing should be restored on next launch.
      expect(persisted.last, isNull);
    });

    test('a session survives the app being killed mid-shift', () async {
      final startedAt = DateTime(2026, 8, 11, 6, 2);
      final restored = DrivingSession(
        id: 'session-1',
        startedAt: startedAt,
        platform: WorkPlatform.uber,
        distanceMeters: 8000,
        vehicleCostPerMile: .30,
      );

      final controller = build(restored: restored);
      await controller.resumeIfActive();

      expect(controller.isDriving, isTrue);
      expect(tracker.started, isTrue);

      // Mileage banked before the kill is carried forward, not restarted.
      final resumeTime = startedAt.add(const Duration(hours: 1));
      await tracker.emit(at(37.0, -122.0, resumeTime));
      await tracker.emit(
        at(37.01, -122.0, resumeTime.add(const Duration(minutes: 1))),
      );
      expect(controller.session!.distanceMeters, greaterThan(8000));

      final draft = await controller.end(
        now: startedAt.add(const Duration(hours: 5)),
      );
      expect(draft!.hours, closeTo(5, .001));
    });

    test('asks for the disclosure only when permission is missing', () async {
      tracker.permission = LocationPermissionState.always;
      expect(await build().needsPermissionRequest(), isFalse);

      tracker.permission = LocationPermissionState.whileInUse;
      // Foreground-only still needs asking: the escalation to background is
      // the whole point of the prompt.
      expect(await build().needsPermissionRequest(), isTrue);

      tracker.permission = LocationPermissionState.denied;
      expect(await build().needsPermissionRequest(), isTrue);
    });

    test('upgrading to background clears the warning when granted', () async {
      tracker.permission = LocationPermissionState.whileInUse;
      tracker.permissionAfterUpgrade = LocationPermissionState.always;
      final controller = build();
      await controller.start(
        platform: WorkPlatform.uber,
        vehicleCostPerMile: .30,
      );
      expect(controller.backgroundLimited, isTrue);

      final granted = await controller.upgradeToBackgroundTracking();

      expect(granted, isTrue);
      expect(tracker.upgradeRequested, isTrue);
      expect(controller.backgroundLimited, isFalse);
    });

    test('a refused upgrade leaves the warning in place', () async {
      tracker.permission = LocationPermissionState.whileInUse;
      // The OS declined to re-prompt, which it is entitled to do.
      tracker.permissionAfterUpgrade = null;
      final controller = build();
      await controller.start(
        platform: WorkPlatform.uber,
        vehicleCostPerMile: .30,
      );

      final granted = await controller.upgradeToBackgroundTracking();

      expect(granted, isFalse);
      // Never claim background tracking the platform did not actually grant.
      expect(controller.backgroundLimited, isTrue);
    });

    test('discard abandons a session without creating a shift', () async {
      final controller = build();
      await controller.start(
        platform: WorkPlatform.uber,
        vehicleCostPerMile: .30,
      );

      await controller.discard();

      expect(controller.isDriving, isFalse);
      expect(persisted.last, isNull);
    });
  });
}
