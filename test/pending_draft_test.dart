import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/driving/domain/driver_location.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_location_tracker.dart';

/// Tracked hours and miles cannot be re-driven. Everything here exists to prove
/// the app never throws them away without the driver saying so.
void main() {
  /// A shift that was tracked but never priced.
  Shift draft({String id = 'tracked-1'}) => Shift(
    id: id,
    platform: WorkPlatform.uber,
    gross: 0,
    hours: 5.25,
    miles: 112.4,
    directExpenses: 0,
    vehicleCostPerMile: 0.30,
    completedAt: DateTime.now().subtract(const Duration(hours: 1)),
    source: ShiftSource.tracked,
  );

  testWidgets('backing out of the earnings screen keeps the tracked shift', (
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

    now = startedAt.add(const Duration(hours: 5, minutes: 15));
    await tester.tap(find.byKey(const ValueKey('end-shift-button')));
    await tester.pumpAndSettle();

    expect(find.text('How much did you earn?'), findsOneWidget);
    // Banked before the screen opens, so an OS kill here would not lose it.
    expect(store.snapshot.pendingDraft, isNotNull);
    expect(store.snapshot.pendingDraft!.hours, closeTo(5.25, .01));

    // The driver backs out without entering earnings.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The shift is not saved yet, but it is not gone either.
    expect(store.snapshot.shifts, isEmpty);
    expect(store.snapshot.pendingDraft, isNotNull);
    expect(find.byKey(const ValueKey('pending-draft-card')), findsOneWidget);
    expect(find.textContaining('5h 15m'), findsOneWidget);
  });

  testWidgets('a pending draft survives relaunch and can be completed', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', pendingDraft: draft()),
    );

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    // The app comes back offering the shift, not silently missing it.
    expect(find.byKey(const ValueKey('pending-draft-card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('resume-draft-button')));
    await tester.pumpAndSettle();

    expect(find.text('How much did you earn?'), findsOneWidget);
    // The tracked figures came back with it.
    expect(
      find.byKey(const ValueKey('tracked-session-summary')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).at(0), '312');
    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    final saved = store.snapshot.shifts.single;
    expect(saved.gross, 312);
    expect(saved.hours, closeTo(5.25, .01));
    expect(saved.source, ShiftSource.tracked);
    // Saving is what retires the draft, so the card does not linger.
    expect(store.snapshot.pendingDraft, isNull);
    expect(find.byKey(const ValueKey('pending-draft-card')), findsNothing);
  });

  testWidgets('discarding a tracked shift requires confirmation', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', pendingDraft: draft()),
    );

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('discard-draft-button')));
    await tester.pumpAndSettle();

    // Keeping is the safe default, and it must actually keep.
    expect(find.text('Discard tracked shift?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(store.snapshot.pendingDraft, isNotNull);

    await tester.tap(find.byKey(const ValueKey('discard-draft-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-discard-draft')));
    await tester.pumpAndSettle();

    // Only an explicit confirmation throws the driving away.
    expect(store.snapshot.pendingDraft, isNull);
    expect(store.snapshot.shifts, isEmpty);
    expect(find.byKey(const ValueKey('pending-draft-card')), findsNothing);
  });

  test('a pending draft round-trips through the snapshot', () {
    final snapshot = AppSnapshot(driverName: 'Ahmed', pendingDraft: draft());
    final restored = AppSnapshot.fromJson(snapshot.toJson());

    expect(restored.pendingDraft, isNotNull);
    expect(restored.pendingDraft!.id, 'tracked-1');
    expect(restored.pendingDraft!.miles, 112.4);
    expect(restored.pendingDraft!.source, ShiftSource.tracked);
  });

  test('a damaged draft is dropped without taking history with it', () {
    final json = AppSnapshot(
      driverName: 'Ahmed',
      shifts: [draft(id: 'tracked-9')],
      pendingDraft: draft(),
    ).toJson();
    // A non-finite number is exactly what Shift.fromJson rejects.
    (json['pendingDraft']! as Map<String, Object?>)['miles'] = 'not-a-number';

    final restored = AppSnapshot.fromJson(json);

    expect(restored.pendingDraft, isNull);
    expect(restored.shifts, hasLength(1));
  });
}
