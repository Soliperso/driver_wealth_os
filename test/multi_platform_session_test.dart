import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/driving/application/driving_session_controller.dart';
import 'package:driver_wealth_os/features/driving/domain/driver_location.dart';
import 'package:driver_wealth_os/features/driving/domain/driving_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_location_tracker.dart';

DriverLocation at(double lat, double lon, DateTime time) => DriverLocation(
  latitude: lat,
  longitude: lon,
  timestamp: time,
  accuracyMeters: 5,
);

void main() {
  final t0 = DateTime(2026, 8, 14, 16);

  DrivingSession sessionOn(List<WorkPlatform> platforms) => DrivingSession(
    id: 'session-1',
    startedAt: t0,
    platformSpans: [
      for (final platform in platforms)
        PlatformSpan(platform: platform, from: t0),
    ],
  );

  group('switching apps mid-shift', () {
    test('adding one opens a span without touching the clock', () {
      final session = sessionOn([WorkPlatform.uber]);
      final withLyft = session.addingPlatform(
        WorkPlatform.lyft,
        at: t0.add(const Duration(hours: 3)),
      );

      // The whole point of doing this in place: the shift keeps running.
      expect(withLyft.startedAt, t0);
      expect(withLyft.isActive, isTrue);
      expect(withLyft.livePlatforms, [WorkPlatform.uber, WorkPlatform.lyft]);

      final lyftSpan = withLyft.platformSpans.last;
      expect(lyftSpan.from, t0.add(const Duration(hours: 3)));
      expect(lyftSpan.isLive, isTrue);
    });

    test('adding an app that is already live changes nothing', () {
      final session = sessionOn([WorkPlatform.uber]);

      expect(
        identical(session.addingPlatform(WorkPlatform.uber, at: t0), session),
        isTrue,
      );
    });

    test('removing closes the span but keeps the app on the shift', () {
      final at = t0.add(const Duration(hours: 5));
      final session = sessionOn([
        WorkPlatform.uber,
        WorkPlatform.lyft,
      ]).removingPlatform(WorkPlatform.lyft, at: at);

      expect(session.livePlatforms, [WorkPlatform.uber]);
      // Still owed an earnings line: Lyft paid for the hours it was on.
      expect(session.platforms, [WorkPlatform.uber, WorkPlatform.lyft]);
      expect(session.platformSpans.last.to, at);
    });

    test('refuses to remove the last live app', () {
      final session = sessionOn([WorkPlatform.uber]);

      final after = session.removingPlatform(
        WorkPlatform.uber,
        at: t0.add(const Duration(hours: 1)),
      );

      // A session running nothing has no one to attribute earnings to. Ending
      // the shift is the separate, deliberate action for that.
      expect(identical(after, session), isTrue);
      expect(after.livePlatforms, [WorkPlatform.uber]);
    });

    test('switching an app back on opens a second span, not a longer one', () {
      final session = sessionOn([WorkPlatform.uber, WorkPlatform.lyft])
          .removingPlatform(
            WorkPlatform.lyft,
            at: t0.add(const Duration(hours: 2)),
          )
          .addingPlatform(
            WorkPlatform.lyft,
            at: t0.add(const Duration(hours: 4)),
          );

      final lyftSpans = session.platformSpans
          .where((span) => span.platform == WorkPlatform.lyft)
          .toList();

      // Flattening these into one span would claim Lyft was live through the
      // two hours it was switched off.
      expect(lyftSpans.length, 2);
      expect(lyftSpans.first.to, t0.add(const Duration(hours: 2)));
      expect(lyftSpans.last.from, t0.add(const Duration(hours: 4)));
      expect(session.platforms, [WorkPlatform.uber, WorkPlatform.lyft]);
    });

    test('an app cannot be live before the shift began', () {
      final session = sessionOn([
        WorkPlatform.uber,
      ]).addingPlatform(WorkPlatform.lyft, at: t0.subtract(Duration(days: 1)));

      expect(session.platformSpans.last.from, t0);
    });
  });

  group('the shift a multi-app session produces', () {
    test('carries one earnings line per app, all at zero', () {
      final session = sessionOn([WorkPlatform.uber, WorkPlatform.lyft]);
      final draft = session.toDraftShift(
        endedAt: t0.add(const Duration(hours: 6)),
      );

      expect(draft.earnings, {WorkPlatform.uber: 0.0, WorkPlatform.lyft: 0.0});
      expect(draft.isMultiApp, isTrue);
      // Counted once for the shift, not once per app.
      expect(draft.hours, 6);
    });

    test('includes an app that was switched off before the end', () {
      final session = sessionOn([
        WorkPlatform.uber,
        WorkPlatform.lyft,
      ]).removingPlatform(WorkPlatform.lyft, at: t0.add(Duration(hours: 2)));

      final draft = session.toDraftShift(
        endedAt: t0.add(const Duration(hours: 6)),
      );

      // Dropping Lyft here would lose whatever it paid for those two hours.
      expect(draft.earnings.keys, [WorkPlatform.uber, WorkPlatform.lyft]);
    });
  });

  group('storage', () {
    test('round trips every span', () {
      final session = sessionOn([
        WorkPlatform.uber,
        WorkPlatform.lyft,
      ]).removingPlatform(WorkPlatform.lyft, at: t0.add(Duration(hours: 2)));

      final restored = DrivingSession.fromJson(session.toJson())!;

      expect(restored.livePlatforms, [WorkPlatform.uber]);
      expect(restored.platforms, [WorkPlatform.uber, WorkPlatform.lyft]);
      expect(restored.platformSpans.last.to, t0.add(const Duration(hours: 2)));
    });

    test('restores a session stored before spans existed', () {
      final legacy = {
        'id': 'session-old',
        'startedAt': t0.toIso8601String(),
        'endedAt': null,
        'platform': 'doordash',
        'distanceMeters': 1609.344,
        'vehicleCostPerMile': 0.30,
        'pausedAt': null,
        'pausedMillis': 0,
      };

      final restored = DrivingSession.fromJson(legacy)!;

      expect(restored.livePlatforms, [WorkPlatform.doorDash]);
      expect(restored.platformSpans.single.from, t0);
      expect(restored.miles, closeTo(1, .001));
    });
  });

  group('the controller', () {
    late FakeLocationTracker tracker;
    late List<DrivingSession?> persisted;

    DrivingSessionController build() => DrivingSessionController(
      tracker: tracker,
      persist: (session) async => persisted.add(session),
    );

    setUp(() {
      tracker = FakeLocationTracker();
      persisted = [];
    });

    tearDown(() => tracker.dispose());

    test('starts a shift running two apps at once', () async {
      final controller = build();

      await controller.start(
        platforms: {WorkPlatform.uber, WorkPlatform.lyft},
        vehicleCostPerMile: .30,
        now: t0,
      );

      expect(controller.session!.livePlatforms, [
        WorkPlatform.uber,
        WorkPlatform.lyft,
      ]);
      // One session, one clock, one odometer.
      expect(controller.session!.startedAt, t0);
    });

    test('adding an app mid-shift keeps the time and mileage intact', () async {
      final controller = build();
      await controller.start(
        platforms: {WorkPlatform.uber},
        vehicleCostPerMile: .30,
        now: t0,
      );
      await tracker.emit(at(37.0, -122.0, t0));
      await tracker.emit(at(37.01, -122.0, t0.add(const Duration(minutes: 1))));
      final milesBefore = controller.trackedMiles;

      final added = await controller.addPlatform(
        WorkPlatform.lyft,
        now: t0.add(const Duration(hours: 3)),
      );

      expect(added, isTrue);
      expect(controller.trackedMiles, milesBefore);
      expect(controller.session!.startedAt, t0);
      expect(controller.isDriving, isTrue);
      // Persisted immediately, so a kill right after does not lose the change.
      expect(persisted.last!.livePlatforms, [
        WorkPlatform.uber,
        WorkPlatform.lyft,
      ]);
    });

    test('removing the only live app is refused', () async {
      final controller = build();
      await controller.start(
        platforms: {WorkPlatform.uber},
        vehicleCostPerMile: .30,
        now: t0,
      );

      expect(await controller.removePlatform(WorkPlatform.uber), isFalse);
      expect(controller.session!.livePlatforms, [WorkPlatform.uber]);
    });

    test('ending closes every span and bills the apps once', () async {
      final controller = build();
      await controller.start(
        platforms: {WorkPlatform.uber, WorkPlatform.lyft},
        vehicleCostPerMile: .30,
        now: t0,
      );

      final draft = await controller.end(now: t0.add(const Duration(hours: 6)));

      expect(draft!.earnings.keys, [WorkPlatform.uber, WorkPlatform.lyft]);
      expect(draft.hours, 6);
      expect(draft.gross, 0);
    });
  });
}
