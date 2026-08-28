import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/driving/application/location_tracker.dart';
import 'package:driver_wealth_os/features/driving/domain/driver_location.dart';
import 'package:driver_wealth_os/features/driving/domain/driving_session.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_location_tracker.dart';

void main() {
  testWidgets('start driving, track, end shift, then enter earnings', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));

    // A real shift: started at 6:02, ended at 11:17. Without a controllable
    // clock the session would last microseconds and produce a zero-hour shift.
    final startedAt = DateTime(2026, 8, 11, 6, 2);
    var now = startedAt;

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        // Freeze the live clock so the tree can reach a settled frame.
        drivingRefreshInterval: null,
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();

    // Idle state offers the primary action.
    expect(find.byKey(const ValueKey('start-driving-card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('start-driving-button')));
    await tester.pumpAndSettle();

    // Platform is captured up front rather than recalled hours later.
    await tester.tap(find.byKey(const ValueKey('start-platform-uber')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driving-session-active')),
      findsOneWidget,
    );
    expect(find.text('Driving'), findsOneWidget);
    expect(find.text('Uber'), findsNothing);
    expect(store.snapshot.activeSession, isNotNull);

    // Drive a measurable distance.
    await tracker.emit(
      DriverLocation(latitude: 37.0, longitude: -122.0, timestamp: startedAt),
    );
    await tracker.emit(
      DriverLocation(
        latitude: 37.03,
        longitude: -122.0,
        timestamp: startedAt.add(const Duration(minutes: 4)),
      ),
    );
    await tester.pump();

    // Five and a quarter hours later.
    now = startedAt.add(const Duration(hours: 5, minutes: 15));
    // The live card is taller than the 800×600 test viewport, so the button at
    // its foot has to be scrolled to before it can be tapped.
    await tester.ensureVisible(find.byKey(const ValueKey('end-shift-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('end-shift-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    // Earnings entry, framed around the money because time and miles are known.
    expect(find.text('How much did you earn?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tracked-session-summary')),
      findsOneWidget,
    );
    // The active session must be cleared so a relaunch does not resume it.
    expect(store.snapshot.activeSession, isNull);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '287');
    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    final saved = store.snapshot.shifts.single;
    expect(saved.source, ShiftSource.tracked);
    expect(saved.gross, 287);
    expect(saved.miles, greaterThan(2));
    expect(saved.hours, closeTo(5.25, .01));
    expect(saved.platform, WorkPlatform.uber);
    // Time and miles were measured; only the money came from the driver.
    expect(saved.netProfit, lessThan(287));
  });

  testWidgets('the disclosure is shown before the OS prompt, and can be '
      'declined without starting anything', (tester) async {
    // Foreground-only: the app still needs to ask, so the disclosure applies.
    final tracker = FakeLocationTracker(
      permission: LocationPermissionState.whileInUse,
    );
    addTearDown(tracker.dispose);
    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('start-driving-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-platform-uber')));
    await tester.pumpAndSettle();

    // Explained before the system dialog, not after.
    expect(find.text('Why Driver Wealth needs your location'), findsOneWidget);
    expect(
      find.textContaining('Only during a shift you started'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('location-disclosure-decline')));
    await tester.pumpAndSettle();

    // Proves the tap actually landed. Without this the test would still pass
    // if the button were off-screen, since a missed tap and a decline look
    // identical from the outside.
    expect(find.text('Why Driver Wealth needs your location'), findsNothing);

    // Declining is a real answer: nothing was started and nothing persisted.
    expect(find.byKey(const ValueKey('driving-session-active')), findsNothing);
    expect(store.snapshot.activeSession, isNull);
    expect(tracker.started, isFalse);
    // The manual route stays available to a driver who said no.
    expect(find.text('Enter a session manually'), findsOneWidget);
  });

  testWidgets('accepting the disclosure starts a shift and warns that only '
      'foreground location was granted', (tester) async {
    final tracker = FakeLocationTracker(
      permission: LocationPermissionState.whileInUse,
    );
    addTearDown(tracker.dispose);
    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('start-driving-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-platform-uber')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('location-disclosure-continue')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('driving-session-active')),
      findsOneWidget,
    );
    // Under-counted miles inflate profit, so the limitation is stated rather
    // than left for the driver to discover in a wrong number.
    expect(
      find.byKey(const ValueKey('background-limited-notice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('upgrade-background-button')),
      findsOneWidget,
    );
  });

  testWidgets('a session running at launch is resumed, not lost', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);

    final startedAt = DateTime.now().subtract(const Duration(hours: 2));
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        activeSession: DrivingSession.single(
          id: 'session-1',
          startedAt: startedAt,
          platform: WorkPlatform.lyft,
          distanceMeters: 16000,
        ),
      ),
    );

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        // Freeze the live clock so the tree can reach a settled frame.
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    // The driver comes back to a running shift with its time and miles intact,
    // rather than an app that quietly forgot it was tracking.
    expect(
      find.byKey(const ValueKey('driving-session-active')),
      findsOneWidget,
    );
    expect(find.textContaining('9.9 mi'), findsOneWidget);
    expect(find.textContaining('02:0'), findsOneWidget);
  });

  testWidgets('a break is excluded from the hours the shift saves', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));

    final startedAt = DateTime(2026, 8, 11, 6, 2);
    var now = startedAt;

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        drivingRefreshInterval: null,
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('start-driving-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-platform-uber')));
    await tester.pumpAndSettle();

    await tracker.emit(
      DriverLocation(latitude: 37.0, longitude: -122.0, timestamp: startedAt),
    );
    await tracker.emit(
      DriverLocation(
        latitude: 37.03,
        longitude: -122.0,
        timestamp: startedAt.add(const Duration(minutes: 4)),
      ),
    );
    await tester.pump();

    // Two hours in, the driver stops for lunch.
    now = startedAt.add(const Duration(hours: 2));
    await tester.ensureVisible(
      find.byKey(const ValueKey('pause-shift-button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pause-shift-button')));
    await tester.pumpAndSettle();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Driving'), findsNothing);
    expect(store.snapshot.activeSession!.isPaused, isTrue);
    // Two things are deliberately left to other tests. That the location
    // stream is torn down is asserted in driving_session_test, because the
    // platform teardown does not complete inside testWidgets' fake async. And
    // the warning threshold has its own test below, because the card measures
    // the break against DateTime.now() rather than the injected clock these
    // fixed dates drive.

    // Forty-five minutes later they are back on the road.
    now = startedAt.add(const Duration(hours: 2, minutes: 45));
    await tester.ensureVisible(
      find.byKey(const ValueKey('resume-shift-button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('resume-shift-button')));
    await tester.pumpAndSettle();

    expect(find.text('Driving'), findsOneWidget);
    expect(store.snapshot.activeSession!.isPaused, isFalse);

    // Finishing at 11:17 wall clock, but only 4.5 hours of it were worked.
    now = startedAt.add(const Duration(hours: 5, minutes: 15));
    // The live card is taller than the 800×600 test viewport, so the button at
    // its foot has to be scrolled to before it can be tapped.
    await tester.ensureVisible(find.byKey(const ValueKey('end-shift-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('end-shift-button')));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '287');
    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    final saved = store.snapshot.shifts.single;
    expect(saved.hours, closeTo(4.5, .01));
    // The break took time off the shift; it must not have taken miles off it.
    expect(saved.miles, greaterThan(2));
  });

  testWidgets('a long break is called out rather than left to run', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);

    final startedAt = DateTime.now().subtract(const Duration(hours: 3));
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        activeSession: DrivingSession.single(
          id: 'session-1',
          startedAt: startedAt,
          platform: WorkPlatform.uber,
          distanceMeters: 16000,
          // Paused 40 minutes ago: past the warning, short of the auto-end.
          pausedAt: DateTime.now().subtract(const Duration(minutes: 40)),
        ),
      ),
    );

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paused-notice')), findsOneWidget);
    expect(find.textContaining('Paused for 40m'), findsOneWidget);
    // The session is still the driver's to resume — warned, not ended.
    expect(store.snapshot.activeSession, isNotNull);
  });

  testWidgets('a forgotten break ends itself into a recoverable draft', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);

    final startedAt = DateTime.now().subtract(const Duration(hours: 9));
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        activeSession: DrivingSession.single(
          id: 'session-1',
          startedAt: startedAt,
          platform: WorkPlatform.uber,
          distanceMeters: 16000,
          // Paused six hours ago and never resumed.
          pausedAt: startedAt.add(const Duration(hours: 3)),
        ),
      ),
    );

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    // Closed out on the way in, so nothing keeps counting.
    expect(store.snapshot.activeSession, isNull);
    expect(find.byKey(const ValueKey('driving-session-active')), findsNothing);

    // The hours are not lost: they are waiting on the recovery card, cut off
    // where the driver actually stopped rather than where they were noticed.
    expect(find.byKey(const ValueKey('pending-draft-card')), findsOneWidget);
    expect(store.snapshot.pendingDraft!.hours, closeTo(3, .01));
    // No earnings form was thrown in front of whatever they were doing.
    expect(find.text('How much did you earn?'), findsNothing);
  });

  testWidgets('cancelling a session throws it away, and asks first', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);

    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        activeSession: DrivingSession.single(
          id: 'session-1',
          startedAt: DateTime.now().subtract(const Duration(hours: 2)),
          platform: WorkPlatform.uber,
          distanceMeters: 16000,
        ),
      ),
    );

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('cancel-session-button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cancel-session-button')));
    await tester.pumpAndSettle();

    // Backing out of the dialog leaves the shift exactly as it was.
    await tester.tap(find.text('Keep driving'));
    await tester.pumpAndSettle();
    expect(store.snapshot.activeSession, isNotNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('cancel-session-button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cancel-session-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-cancel-session')));
    await tester.pumpAndSettle();

    // Gone, and unlike End session it banks no draft to come back to.
    expect(store.snapshot.activeSession, isNull);
    expect(store.snapshot.pendingDraft, isNull);
    expect(find.byKey(const ValueKey('driving-session-active')), findsNothing);
    expect(find.text('How much did you earn?'), findsNothing);
  });
}
