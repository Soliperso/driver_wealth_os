import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
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
    expect(find.text('DRIVING'), findsOneWidget);
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

  testWidgets('a session running at launch is resumed, not lost', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);

    final startedAt = DateTime.now().subtract(const Duration(hours: 2));
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        activeSession: DrivingSession(
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
    expect(find.textContaining('9.9 miles'), findsOneWidget);
    expect(find.textContaining('02:0'), findsOneWidget);
  });
}
