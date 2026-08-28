import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/driving/domain/driver_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_location_tracker.dart';

void main() {
  testWidgets('running two apps at once records one shift with two earnings '
      'lines', (tester) async {
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

    // The `+` on each row builds a combination instead of starting straight
    // away, which is how a driver says "Uber *and* Lyft".
    await tester.tap(find.byKey(const ValueKey('add-platform-uber')));
    await tester.pumpAndSettle();
    // The confirm button appearing shortens the list, so the later rows may
    // need scrolling to on a small screen.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('add-platform-lyft')),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('add-platform-lyft')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-selected-platforms')));
    await tester.pumpAndSettle();

    // One session, both apps live on it.
    expect(
      find.byKey(const ValueKey('driving-session-active')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('app-chip-uber')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-chip-lyft')), findsOneWidget);
    expect(store.snapshot.activeSession!.livePlatforms, [
      WorkPlatform.uber,
      WorkPlatform.lyft,
    ]);

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

    now = startedAt.add(const Duration(hours: 6));
    await tester.ensureVisible(find.byKey(const ValueKey('end-shift-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('end-shift-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    // A money field per app, seeded from what the session was running.
    expect(find.text('Uber earnings'), findsOneWidget);
    expect(find.text('Lyft earnings'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('gross-field-0')),
      '142.50',
    );
    await tester.enterText(find.byKey(const ValueKey('gross-field-1')), '38');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    final saved = store.snapshot.shifts.single;
    expect(saved.earnings, {
      WorkPlatform.uber: 142.50,
      WorkPlatform.lyft: 38.0,
    });
    expect(saved.gross, 180.50);
    // The point of the whole design: six hours and the miles are counted once
    // for the shift, not once per app.
    expect(saved.hours, closeTo(6, .01));
    expect(saved.miles, greaterThan(2));
    expect(saved.isMultiApp, isTrue);
  });

  testWidgets('an app can be switched on and off without ending the shift', (
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

    // The common case is untouched: one tap on a row starts that app alone.
    await tester.tap(find.byKey(const ValueKey('start-driving-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-platform-uber')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-chip-uber')), findsOneWidget);
    // Nothing to remove while it is the only app running.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('app-chip-uber')),
        matching: find.byIcon(Icons.close_rounded),
      ),
      findsNothing,
    );

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
    final milesBefore = store.snapshot.activeSession!.miles;

    // Three hours in, Lyft goes on too.
    now = startedAt.add(const Duration(hours: 3));
    await tester.tap(find.byKey(const ValueKey('add-app-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-platform-lyft')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-chip-lyft')), findsOneWidget);
    final session = store.snapshot.activeSession!;
    expect(session.livePlatforms, [WorkPlatform.uber, WorkPlatform.lyft]);
    // Adding an app must not disturb the shift already in progress.
    expect(session.startedAt, startedAt);
    expect(session.miles, milesBefore);

    // Two hours later Lyft goes off again — the shift keeps running on Uber.
    now = startedAt.add(const Duration(hours: 5));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('app-chip-lyft')),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-chip-lyft')), findsNothing);
    expect(
      find.byKey(const ValueKey('driving-session-active')),
      findsOneWidget,
    );
    expect(store.snapshot.activeSession!.livePlatforms, [WorkPlatform.uber]);

    now = startedAt.add(const Duration(hours: 7));
    await tester.ensureVisible(find.byKey(const ValueKey('end-shift-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('end-shift-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    // Lyft still gets a money field: it paid for the two hours it was on.
    expect(find.text('Uber earnings'), findsOneWidget);
    expect(find.text('Lyft earnings'), findsOneWidget);
  });

  testWidgets('a manual shift can be split across apps by hand', (
    tester,
  ) async {
    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));

    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter a session manually'));
    await tester.pumpAndSettle();

    // One platform to start with, exactly as before.
    expect(find.text('Platform'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('add-earnings-line')));
    await tester.tap(find.byKey(const ValueKey('add-earnings-line')));
    await tester.pumpAndSettle();

    // Now labelled per app, and the second line defaults to an app the first
    // one is not already using.
    expect(find.text('App 1'), findsOneWidget);
    expect(find.text('App 2'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('gross-field-0')), '120');
    await tester.enterText(find.byKey(const ValueKey('gross-field-1')), '80');
    await tester.enterText(find.byType(TextFormField).at(2), '5');
    await tester.enterText(find.byType(TextFormField).at(3), '100');
    await tester.enterText(find.byType(TextFormField).at(4), '10');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    final saved = store.snapshot.shifts.single;
    expect(saved.gross, 200);
    expect(saved.earnings.length, 2);
    expect(saved.hours, 5);
    expect(saved.miles, 100);
  });
}
