import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/core/sync/sync_service.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/auth/domain/auth_user.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_location_tracker.dart';

/// Records what it was asked to sync so the app's bookkeeping can be asserted
/// without a backend.
class RecordingSyncService implements SyncService {
  final calls = <AppSnapshot>[];

  /// What to hand back. Null means "return the snapshot unchanged, with its
  /// dirty markers cleared" — what a successful sync does.
  AppSnapshot? nextResult;

  /// When set, [sync] throws it, standing in for being offline.
  Object? failure;

  @override
  Future<AppSnapshot> sync(AppSnapshot local) async {
    calls.add(local);
    final error = failure;
    if (error != null) throw error;
    return nextResult ??
        local.copyWith(
          dirtyShiftIds: const {},
          deletedShiftIds: const {},
          dirtyPreferences: false,
          dirtyGoal: false,
          syncCursor: DateTime.utc(2026, 8, 12),
        );
  }
}

void main() {
  Shift shift(String id, {double gross = 200}) => Shift.single(
    id: id,
    platform: WorkPlatform.uber,
    gross: gross,
    hours: 5,
    miles: 100,
    directExpenses: 20,
    vehicleCostPerMile: .20,
    completedAt: DateTime(2026, 8, 11, 18),
  );

  Map<String, Object?> row(
    String id, {
    String gross = '200.00',
    String? deletedAt,
    String source = 'manual',
    // Absent rather than null by default, so the pre-column case is what the
    // other tests exercise unless one asks for the flag explicitly.
    bool? costsReviewed,
  }) => {
    'id': id,
    'platform': 'uber',
    // PostgREST returns `numeric` as a string, which is the detail most likely
    // to silently zero every money value if it is ever mishandled.
    'gross': gross,
    'hours': '5.0000',
    'miles': '100.00',
    'direct_expenses': '20.00',
    'vehicle_cost_per_mile': '0.2000',
    'completed_at': '2026-08-11T18:00:00Z',
    'source': source,
    'costs_reviewed': ?costsReviewed,
    'deleted_at': deletedAt,
  };

  group('merge rules', () {
    test('an incoming shift this device has never seen is added', () {
      final merged = mergePulledShifts(const AppSnapshot(), [row('remote-1')]);

      expect(merged.shifts, hasLength(1));
      expect(merged.shifts.single.id, 'remote-1');
      // Proves the numeric-as-string handling: a naive cast would give 0.
      expect(merged.shifts.single.gross, 200);
    });

    test('a locally edited shift beats the incoming copy', () {
      final local = AppSnapshot(
        shifts: [shift('a', gross: 999)],
        dirtyShiftIds: const {'a'},
      );

      final merged = mergePulledShifts(local, [row('a', gross: '100.00')]);

      // The driver is looking at 999. An unpushed local edit is by definition
      // newer than anything the server can be holding.
      expect(merged.shifts.single.gross, 999);
    });

    test('a locally deleted shift is not resurrected', () {
      const local = AppSnapshot(deletedShiftIds: {'a'});

      final merged = mergePulledShifts(local, [row('a')]);

      expect(merged.shifts, isEmpty);
    });

    test('a tombstone removes the shift here', () {
      final local = AppSnapshot(shifts: [shift('a')]);

      final merged = mergePulledShifts(local, [
        row('a', deletedAt: '2026-08-12T00:00:00Z'),
      ]);

      expect(merged.shifts, isEmpty);
    });

    test('a clean local shift is overwritten by the incoming copy', () {
      final local = AppSnapshot(shifts: [shift('a', gross: 100)]);

      final merged = mergePulledShifts(local, [row('a', gross: '250.00')]);

      // Not dirty here, so the other device wrote it more recently.
      expect(merged.shifts.single.gross, 250);
    });

    test('one malformed row does not discard the rest of the sync', () {
      final merged = mergePulledShifts(const AppSnapshot(), [
        {'id': 'broken', 'completed_at': 'not-a-date'},
        row('good'),
      ]);

      expect(merged.shifts.map((shift) => shift.id), ['good']);
    });

    test('an imported shift awaiting its costs survives a pull unreviewed', () {
      final merged = mergePulledShifts(const AppSnapshot(), [
        row(
          'imported:uber:2026-08-11',
          source: 'imported',
          costsReviewed: false,
        ),
      ]);

      // Losing this flag marks the shift reviewed, which drops it out of the
      // History cost-review notice and lets it into the platform comparison
      // with no fuel, tolls or parking — overstating profit.
      expect(merged.shifts.single.costsReviewed, isFalse);
    });

    test('a reviewed import stays reviewed', () {
      final merged = mergePulledShifts(const AppSnapshot(), [
        row(
          'imported:uber:2026-08-11',
          source: 'imported',
          costsReviewed: true,
        ),
      ]);

      expect(merged.shifts.single.costsReviewed, isTrue);
    });

    test('a row predating the column infers the flag from its source', () {
      final merged = mergePulledShifts(const AppSnapshot(), [
        row('old-manual'),
        row('old-import', source: 'imported'),
      ]);

      final byId = {for (final shift in merged.shifts) shift.id: shift};
      // The same rule the local decoder applies: only an import can arrive
      // without the driver's own cost figures.
      expect(byId['old-manual']!.costsReviewed, isTrue);
      expect(byId['old-import']!.costsReviewed, isFalse);
    });

    test('an empty pull leaves the snapshot identical', () {
      final local = AppSnapshot(shifts: [shift('a')]);

      expect(mergePulledShifts(local, const []), same(local));
    });
  });

  group('app bookkeeping', () {
    Future<RecordingSyncService> pumpSignedIn(
      WidgetTester tester, {
      required MemoryAppStore store,
    }) async {
      final tracker = FakeLocationTracker();
      addTearDown(tracker.dispose);
      final gateway = FakeAuthGateway(
        user: const AuthUser(id: 'user-1', email: 'driver@example.com'),
      );
      addTearDown(gateway.dispose);
      final sync = RecordingSyncService();

      await tester.pumpWidget(
        DriverWealthApp(
          store: store,
          authGateway: gateway,
          syncService: sync,
          locationTracker: tracker,
          drivingRefreshInterval: null,
        ),
      );
      await tester.pumpAndSettle();
      return sync;
    }

    testWidgets('a device with records but no cursor uploads everything', (
      tester,
    ) async {
      // Exactly the state of anyone who used the app before accounts existed.
      final store = MemoryAppStore(
        AppSnapshot(driverName: 'Ahmed', shifts: [shift('a'), shift('b')]),
      );

      final sync = await pumpSignedIn(tester, store: store);

      expect(sync.calls, isNotEmpty);
      final pushed = sync.calls.first;
      expect(pushed.dirtyShiftIds, {'a', 'b'});
      expect(pushed.dirtyPreferences, isTrue);
    });

    testWidgets('saving a shift marks it for upload and clears it after', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(driverName: 'Ahmed', syncCursor: DateTime.utc(2026, 8, 1)),
      );
      final sync = await pumpSignedIn(tester, store: store);
      sync.calls.clear();

      await tester.tap(find.text('Enter a shift manually'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '250');
      await tester.enterText(fields.at(1), '6');
      await tester.enterText(fields.at(2), '120');
      await tester.ensureVisible(find.text('Calculate true profit'));
      await tester.tap(find.text('Calculate true profit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save to Today'));
      await tester.tap(find.text('Save to Today'));
      await tester.pumpAndSettle();

      expect(sync.calls, isNotEmpty);
      expect(sync.calls.last.dirtyShiftIds, hasLength(1));
      // A successful sync retires the marker, so the record is not re-pushed
      // on every subsequent change.
      expect(store.snapshot.dirtyShiftIds, isEmpty);
      expect(store.snapshot.syncCursor, isNotNull);
    });

    testWidgets('deleting a shift leaves a tombstone to push', (tester) async {
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('a')],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      final sync = await pumpSignedIn(tester, store: store);
      sync.calls.clear();

      await tester.tap(find.byIcon(Icons.history_rounded));
      await tester.pumpAndSettle();

      // The weekly chart and DNA grid sit above the list, so the row is below
      // the fold and a lazy ListView has not built it yet.
      final historyRow = find.byKey(const ValueKey('history-shift-a'));
      await tester.scrollUntilVisible(historyRow, 200);
      await Scrollable.ensureVisible(tester.element(historyRow), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(historyRow);
      await tester.pumpAndSettle();
      expect(find.text('Shift details'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Delete shift'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete shift'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Without the tombstone the next pull from another device would bring
      // the shift straight back.
      expect(sync.calls.last.deletedShiftIds, {'a'});
    });

    testWidgets('an offline sync keeps the markers for the next attempt', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('a')],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      final tracker = FakeLocationTracker();
      addTearDown(tracker.dispose);
      final gateway = FakeAuthGateway(
        user: const AuthUser(id: 'user-1', email: 'driver@example.com'),
      );
      addTearDown(gateway.dispose);
      final sync = RecordingSyncService()..failure = Exception('offline');

      await tester.pumpWidget(
        DriverWealthApp(
          store: store,
          authGateway: gateway,
          syncService: sync,
          locationTracker: tracker,
          drivingRefreshInterval: null,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('settings-daily-goal')),
        '400',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-save')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await tester.pumpAndSettle();

      // Offline is the normal case for a driver, not an error state. The
      // change is saved locally and stays queued.
      expect(store.snapshot.dailyGoal, 400);
      expect(store.snapshot.dirtyPreferences, isTrue);
      expect(find.byKey(const ValueKey('storage-error-banner')), findsNothing);
    });
  });
}
