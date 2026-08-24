import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/core/sync/sync_service.dart';
import 'package:driver_wealth_os/features/tax/domain/expense.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same precedence rules `sync_service_test.dart` pins for shifts, over
/// expenses. This is the layer where a mistake silently loses a driver's
/// records rather than showing them a wrong number, so every rule gets a case.
void main() {
  Expense expense(
    String id, {
    double amount = 100,
    ExpenseCategory category = ExpenseCategory.maintenance,
    DateTime? on,
    String note = '',
  }) => Expense(
    id: id,
    amount: amount,
    category: category,
    incurredOn: on ?? DateTime(2026, 5, 1),
    note: note,
  );

  Map<String, Object?> row(
    String id, {
    double amount = 100,
    String category = 'maintenance',
    String incurredOn = '2026-05-01T00:00:00Z',
    String? deletedAt,
    String note = '',
    String? receiptPath,
  }) => {
    'id': id,
    'amount': amount,
    'category': category,
    'incurred_on': incurredOn,
    'note': note,
    'receipt_path': receiptPath,
    'deleted_at': deletedAt,
  };

  test('a pulled expense lands on a device that has none', () {
    final merged = mergePulledExpenses(const AppSnapshot(), [row('a')]);

    expect(merged.expenses, hasLength(1));
    expect(merged.expenses.single.id, 'a');
    expect(merged.expenses.single.amount, 100);
    expect(merged.expenses.single.category, ExpenseCategory.maintenance);
  });

  test('a local edit is not overwritten until it has been pushed', () {
    final local = AppSnapshot(
      expenses: [expense('a', amount: 250)],
      dirtyExpenseIds: const {'a'},
    );

    final merged = mergePulledExpenses(local, [row('a', amount: 100)]);

    // The driver's unsynced correction survives the pull.
    expect(merged.expenses.single.amount, 250);
  });

  test('a local delete is not resurrected by a stale server row', () {
    final local = AppSnapshot(
      expenses: const [],
      deletedExpenseIds: const {'a'},
    );

    final merged = mergePulledExpenses(local, [row('a')]);

    expect(merged.expenses, isEmpty);
  });

  test('a tombstone removes the record from this device', () {
    final local = AppSnapshot(expenses: [expense('a')]);

    final merged = mergePulledExpenses(local, [
      row('a', deletedAt: '2026-05-02T00:00:00Z'),
    ]);

    expect(merged.expenses, isEmpty);
  });

  test('a newer row from another device overwrites', () {
    final local = AppSnapshot(expenses: [expense('a', amount: 100)]);

    final merged = mergePulledExpenses(local, [
      row('a', amount: 175, category: 'insurance', note: 'renewal'),
    ]);

    expect(merged.expenses.single.amount, 175);
    expect(merged.expenses.single.category, ExpenseCategory.insurance);
    expect(merged.expenses.single.note, 'renewal');
  });

  test('one malformed row does not strand every other change', () {
    final merged = mergePulledExpenses(const AppSnapshot(), [
      {'id': '', 'amount': 10},
      {'id': 'no-date', 'amount': 10},
      row('good'),
    ]);

    expect(merged.expenses, hasLength(1));
    expect(merged.expenses.single.id, 'good');
  });

  test('an unrecognised category decodes to other rather than failing', () {
    // The column is free text so the app can add a Schedule C line without a
    // migration; a device on an older build has to keep the record.
    final merged = mergePulledExpenses(const AppSnapshot(), [
      row('a', category: 'a-category-invented-later'),
    ]);

    expect(merged.expenses.single.category, ExpenseCategory.other);
    expect(merged.expenses.single.amount, 100);
  });

  test('expenses come back newest first', () {
    final merged = mergePulledExpenses(const AppSnapshot(), [
      row('old', incurredOn: '2026-01-01T00:00:00Z'),
      row('new', incurredOn: '2026-06-01T00:00:00Z'),
      row('mid', incurredOn: '2026-03-01T00:00:00Z'),
    ]);

    expect(merged.expenses.map((e) => e.id), ['new', 'mid', 'old']);
  });

  test('an empty pull leaves the snapshot untouched', () {
    final local = AppSnapshot(expenses: [expense('a')]);
    expect(mergePulledExpenses(local, const []), same(local));
  });

  group('snapshot persistence', () {
    test('expenses survive a JSON round trip', () {
      final restored = AppSnapshot.fromJson(
        AppSnapshot(
          driverName: 'Ahmed',
          expenses: [
            expense('a', amount: 42.50, category: ExpenseCategory.phone),
            expense('b', amount: 1200, on: DateTime(2026, 2, 3)),
          ],
          dirtyExpenseIds: const {'a'},
          deletedExpenseIds: const {'gone'},
        ).toJson(),
      );

      expect(restored.expenses, hasLength(2));
      expect(restored.expenses.first.amount, 42.50);
      expect(restored.expenses.first.category, ExpenseCategory.phone);
      expect(restored.dirtyExpenseIds, {'a'});
      expect(restored.deletedExpenseIds, {'gone'});
    });

    test('duplicate ids are collapsed, as they are for shifts', () {
      final restored = AppSnapshot.fromJson(
        AppSnapshot(expenses: [expense('a'), expense('a')]).toJson(),
      );

      expect(restored.expenses, hasLength(1));
    });

    test('a snapshot written before expenses existed still loads', () {
      // Every snapshot on every device at the point this ships.
      final legacy = AppSnapshot(driverName: 'Ahmed').toJson()
        ..remove('expenses')
        ..remove('dirtyExpenseIds')
        ..remove('deletedExpenseIds');

      final restored = AppSnapshot.fromJson(legacy);

      expect(restored.driverName, 'Ahmed');
      expect(restored.expenses, isEmpty);
      expect(restored.dirtyExpenseIds, isEmpty);
    });

    test('unsynced expenses count as unsynced changes', () {
      expect(
        const AppSnapshot(dirtyExpenseIds: {'a'}).hasUnsyncedChanges,
        isTrue,
      );
      expect(
        const AppSnapshot(deletedExpenseIds: {'a'}).hasUnsyncedChanges,
        isTrue,
      );
      expect(const AppSnapshot().hasUnsyncedChanges, isFalse);
    });
  });
}
