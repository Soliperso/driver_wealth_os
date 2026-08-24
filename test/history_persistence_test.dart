import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('snapshot restores values and removes duplicate shift ids', () {
    final shift = _shift();
    final restored = AppSnapshot.fromJson(
      AppSnapshot(
        driverName: 'Ahmed',
        dailyGoal: 325,
        shifts: [shift, shift],
      ).toJson(),
    );

    expect(restored.driverName, 'Ahmed');
    expect(restored.dailyGoal, 325);
    expect(restored.shifts, hasLength(1));
    expect(restored.shifts.single.netProfit, 250);
  });

  test('device store writes and reloads the app snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppStore();
    await store.save(
      AppSnapshot(
        driverName: 'Ahmed',
        dailyGoal: 325,
        shifts: [_shift()],
      ),
    );

    final restored = await store.load();

    expect(restored.driverName, 'Ahmed');
    expect(restored.dailyGoal, 325);
    expect(restored.shifts.single.id, 'persisted-1');
  });

  testWidgets('saved state survives app reconstruction', (tester) async {
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', dailyGoal: 300, shifts: [_shift()]),
    );

    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Hi, Ahmed!'), findsOneWidget);
    expect(find.text(r'$250 / $300'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Recent shifts'), 200);
    await tester.scrollUntilVisible(find.text('Uber'), 100);
    expect(find.text('Uber'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Hi, Ahmed!'), findsOneWidget);
    expect(find.text(r'$250 / $300'), findsOneWidget);
  });

  testWidgets('history supports detail, edit, and delete', (tester) async {
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', shifts: [_shift()]),
    );
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    // With one shift, History stays simple and goes straight from the summary
    // to the selected period's rows.
    final historyRow = find.byKey(const ValueKey('history-shift-persisted-1'));
    await tester.scrollUntilVisible(historyRow, 200);
    expect(find.text('Shifts this week'), findsOneWidget);
    expect(historyRow, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(historyRow), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(historyRow);
    await tester.pumpAndSettle();
    expect(find.text('Shift details'), findsOneWidget);
    expect(find.text(r'$250.00'), findsWidgets);

    await tester.ensureVisible(find.text('Edit shift'));
    await tester.tap(find.text('Edit shift'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '350');
    await tester.ensureVisible(find.text('Review updated profit'));
    await tester.tap(find.text('Review updated profit'));
    await tester.pumpAndSettle();
    expect(find.text(r'$300.00'), findsWidgets);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Shift details'), findsOneWidget);
    expect(find.text(r'$300.00'), findsWidgets);
    expect(store.snapshot.shifts.single.gross, 350);

    await tester.ensureVisible(find.text('Delete shift'));
    await tester.tap(find.text('Delete shift'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this shift?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('No shifts yet'), findsOneWidget);
    expect(store.snapshot.shifts, isEmpty);
  });
}

Shift _shift() => Shift.single(
  id: 'persisted-1',
  platform: WorkPlatform.uber,
  gross: 300,
  hours: 8,
  miles: 100,
  directExpenses: 20,
  vehicleCostPerMile: .30,
  completedAt: DateTime.now(),
);
