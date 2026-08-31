import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/core/sync/sync_service.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/auth/domain/auth_user.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/tax/application/receipt_store.dart';
import 'package:driver_wealth_os/features/tax/domain/expense.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_location_tracker.dart';

/// Stands in for the camera. Records what it was asked to throw away, which is
/// the half of receipt handling that leaks images if it is wrong.
class _FakeReceipts implements ReceiptStore {
  _FakeReceipts({this.nextPath = '/tmp/receipt-1.jpg'});

  /// What the next capture returns. Null stands for the driver backing out.
  String? nextPath;
  final captured = <ReceiptSource>[];
  final discarded = <String>[];

  @override
  Future<String?> capture(ReceiptSource source) async {
    captured.add(source);
    return nextPath;
  }

  @override
  Future<void> discard(String? path) async {
    if (path != null) discarded.add(path);
  }
}

/// Expenses were a complete persistence, sync and tax-math stack with no
/// producer and no consumer: `app.dart` held no expense state at all, so a
/// record loaded from disk or pulled from the account was dropped on the next
/// save. These pin the wiring that closes that gap, and the screen that finally
/// reads it.
class _RecordingSync implements SyncService {
  final calls = <AppSnapshot>[];

  /// What to hand back, standing in for what another device has already pushed.
  AppSnapshot? nextResult;

  @override
  Future<AppSnapshot> sync(AppSnapshot local) async {
    calls.add(local);
    return nextResult ??
        local.copyWith(
          dirtyShiftIds: const {},
          deletedShiftIds: const {},
          dirtyExpenseIds: const {},
          deletedExpenseIds: const {},
          dirtyPreferences: false,
          syncCursor: DateTime.utc(2026, 8, 12),
        );
  }
}

void main() {
  Expense expense(
    String id, {
    double amount = 400,
    ExpenseCategory category = ExpenseCategory.vehiclePayment,
    DateTime? on,
  }) => Expense(
    id: id,
    amount: amount,
    category: category,
    incurredOn: on ?? DateTime(DateTime.now().year, 5, 1),
  );

  Shift shift(String id, {double miles = 100}) => Shift.single(
    id: id,
    platform: WorkPlatform.uber,
    gross: 300,
    hours: 6,
    miles: miles,
    directExpenses: 20,
    vehicleCostPerMile: .20,
    completedAt: DateTime.now().subtract(const Duration(days: 1)),
  );

  Future<_RecordingSync> pump(
    WidgetTester tester, {
    required MemoryAppStore store,
    _RecordingSync? sync,
    _FakeReceipts? receipts,
  }) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway(
      user: const AuthUser(id: 'user-1', email: 'driver@example.com'),
    );
    addTearDown(gateway.dispose);
    final service = sync ?? _RecordingSync();

    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        authGateway: gateway,
        syncService: service,
        locationTracker: tracker,
        drivingRefreshInterval: null,
        receiptStore: receipts ?? _FakeReceipts(),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  /// Brings a row into view and taps it.
  ///
  /// `scrollUntilVisible` alone only guarantees the row is built, not that it
  /// is clear of the bottom navigation bar, so a plain tap lands off-screen.
  /// The same pairing the shift tests use.
  Future<void> tapRow(WidgetTester tester, Finder row) async {
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(row), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  group('expense state survives the round trip', () {
    testWidgets('an expense on disk is still there after the next save', (
      tester,
    ) async {
      // The regression this whole feature was blocked on: `_snapshot()` built
      // an AppSnapshot with no `expenses:`, so the first write after load
      // erased whatever had been restored.
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          expenses: [expense('e1')],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );

      await pump(tester, store: store);

      expect(store.snapshot.expenses, hasLength(1));
      expect(store.snapshot.expenses.single.id, 'e1');
    });

    testWidgets('an expense pulled from the account is kept, not dropped', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(driverName: 'Ahmed', syncCursor: DateTime.utc(2026, 8, 1)),
      );
      final sync = _RecordingSync();
      // What another device has already pushed. `_applySnapshot` used to copy
      // eleven fields out of the merged snapshot and ignore this one.
      sync.nextResult = AppSnapshot(
        driverName: 'Ahmed',
        expenses: [expense('from-other-phone')],
        syncCursor: DateTime.utc(2026, 8, 12),
      );

      await pump(tester, store: store, sync: sync);

      expect(store.snapshot.expenses.map((e) => e.id), ['from-other-phone']);
    });

    testWidgets('a device with expenses but no cursor uploads them', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          expenses: [expense('a'), expense('b')],
        ),
      );

      final sync = await pump(tester, store: store);

      expect(sync.calls.first.dirtyExpenseIds, {'a', 'b'});
    });

    testWidgets('signing out leaves no expenses for the next driver', (
      tester,
    ) async {
      // `_clearDeviceRecords` wipes the device precisely so the next person to
      // sign in on this phone cannot see the previous driver's records.
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          expenses: [expense('e1')],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      await pump(tester, store: store);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tapRow(tester, find.byKey(const ValueKey('settings-sign-out')));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(store.snapshot.expenses, isEmpty);
      expect(store.snapshot.dirtyExpenseIds, isEmpty);
      expect(store.snapshot.deletedExpenseIds, isEmpty);
    });
  });

  group('the Taxes tab', () {
    testWidgets('adding an expense records it and queues it for upload', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('s1')],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      final sync = await pump(tester, store: store);
      sync.calls.clear();

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tax-add-expense')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expense-amount-field')),
        '400',
      );
      await tester.tap(find.byKey(const ValueKey('settings-editor-done')));
      await tester.pumpAndSettle();

      expect(store.snapshot.expenses, hasLength(1));
      expect(store.snapshot.expenses.single.amount, 400);
      expect(sync.calls.last.dirtyExpenseIds, hasLength(1));
    });

    testWidgets('a large vehicle expense flips the better method', (
      tester,
    ) async {
      // 100 miles is worth well under $100 at any published rate, so a $4,000
      // car payment has to carry the actual-expenses side.
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('s1')],
          expenses: [expense('big', amount: 4000)],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      await pump(tester, store: store);

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();

      expect(
        find.text('Your actual expenses are worth more this year'),
        findsOneWidget,
      );
    });

    testWidgets('a driver with no records is told what to do about it', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(driverName: 'Ahmed', syncCursor: DateTime.utc(2026, 8, 1)),
      );
      await pump(tester, store: store);

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Nothing to total yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tax-empty-add-expense')),
        findsOneWidget,
      );
    });

    testWidgets('deleting an expense leaves a tombstone to push', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('s1')],
          expenses: [expense('e1')],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      final sync = await pump(tester, store: store);
      sync.calls.clear();

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();

      final row = find.text('Car payment or lease');
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(row), alignment: .5);
      await tester.pumpAndSettle();
      await tester.longPress(row);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.snapshot.expenses, isEmpty);
      // Without the tombstone the next pull would resurrect it.
      expect(sync.calls.last.deletedExpenseIds, {'e1'});
    });
  });

  group('receipts', () {
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tax-add-expense')));
      await tester.pumpAndSettle();
    }

    testWidgets('a photographed receipt is attached to the expense', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('s1')],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      final receipts = _FakeReceipts(nextPath: '/tmp/receipt-a.jpg');
      await pump(tester, store: store, receipts: receipts);

      await openEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('expense-amount-field')),
        '120',
      );
      await tester.tap(find.byKey(const ValueKey('expense-add-receipt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-source-camera')));
      await tester.pumpAndSettle();

      expect(receipts.captured, [ReceiptSource.camera]);
      expect(
        find.byKey(const ValueKey('expense-receipt-thumbnail')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('settings-editor-done')));
      await tester.pumpAndSettle();

      expect(store.snapshot.expenses.single.receiptPath, '/tmp/receipt-a.jpg');
    });

    testWidgets('backing out of the camera attaches nothing', (tester) async {
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('s1')],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      // Null stands for the driver closing the camera without a shot.
      final receipts = _FakeReceipts(nextPath: null);
      await pump(tester, store: store, receipts: receipts);

      await openEditor(tester);
      await tester.tap(find.byKey(const ValueKey('expense-add-receipt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-source-gallery')));
      await tester.pumpAndSettle();

      expect(receipts.captured, [ReceiptSource.gallery]);
      expect(
        find.byKey(const ValueKey('expense-receipt-thumbnail')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('expense-add-receipt')), findsOneWidget);
    });

    testWidgets('removing a receipt clears it and deletes the photo', (
      tester,
    ) async {
      // `copyWith` treats a null receiptPath as "leave it alone" — the sync
      // merge depends on that — so removal needs its own flag, and this is
      // what proves the flag is actually wired to the button.
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('s1')],
          expenses: [
            Expense(
              id: 'e1',
              amount: 90,
              category: ExpenseCategory.supplies,
              incurredOn: DateTime(DateTime.now().year, 5, 1),
              receiptPath: '/tmp/old-receipt.jpg',
            ),
          ],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      final receipts = _FakeReceipts();
      await pump(tester, store: store, receipts: receipts);

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      final row = find.text('Supplies');
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(row), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expense-remove-receipt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-editor-done')));
      await tester.pumpAndSettle();

      expect(store.snapshot.expenses.single.receiptPath, isNull);
      expect(receipts.discarded, contains('/tmp/old-receipt.jpg'));
    });

    testWidgets('deleting an expense takes its photo with it', (tester) async {
      // The image never left this device, so nothing else holds a copy —
      // leaving it behind strands a picture of a card number on the phone.
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('s1')],
          expenses: [
            Expense(
              id: 'e1',
              amount: 90,
              category: ExpenseCategory.supplies,
              incurredOn: DateTime(DateTime.now().year, 5, 1),
              receiptPath: '/tmp/doomed-receipt.jpg',
            ),
          ],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      final receipts = _FakeReceipts();
      await pump(tester, store: store, receipts: receipts);

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      final row = find.text('Supplies');
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(row), alignment: .5);
      await tester.pumpAndSettle();
      await tester.longPress(row);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.snapshot.expenses, isEmpty);
      expect(receipts.discarded, ['/tmp/doomed-receipt.jpg']);
    });
  });

  group('the expense-categories sheet', () {
    testWidgets('shows what the driver actually spent, not the enum length', (
      tester,
    ) async {
      final store = MemoryAppStore(
        AppSnapshot(
          driverName: 'Ahmed',
          shifts: [shift('s1')],
          expenses: [
            expense('e1', amount: 400),
            expense('e2', amount: 60, category: ExpenseCategory.phone),
          ],
          syncCursor: DateTime.utc(2026, 8, 1),
        ),
      );
      await pump(tester, store: store);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      final tile = find.byKey(const ValueKey('settings-expense-categories'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // The year's total, where the count of enum constants ("11") used to be.
      expect(
        find.descendant(of: tile, matching: find.text(r'$460')),
        findsOneWidget,
      );

      await tapRow(tester, tile);

      expect(find.text(r'$400.00'), findsOneWidget);
      expect(find.text(r'$60.00'), findsOneWidget);
    });

    testWidgets(
      'says when the mileage rate has already covered a vehicle cost',
      (tester) async {
        // Lots of miles, one small vehicle cost: standard mileage wins, so the
        // car payment is real but not separately claimable.
        final store = MemoryAppStore(
          AppSnapshot(
            driverName: 'Ahmed',
            shifts: [shift('s1', miles: 10000)],
            expenses: [expense('e1', amount: 50)],
            syncCursor: DateTime.utc(2026, 8, 1),
          ),
        );
        await pump(tester, store: store);

        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
        await tapRow(
          tester,
          find.byKey(const ValueKey('settings-expense-categories')),
        );

        expect(
          find.text('Car and truck expenses · covered by the mileage rate'),
          findsWidgets,
        );
      },
    );
  });
}
