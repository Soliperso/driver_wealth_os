import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation adapts between compact and wide layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(1024, 900);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('weekly, DNA, freedom goal and coach are reachable end to end', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', shifts: _patternShifts()),
    );
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('This week'), findsOneWidget);

    // The weekly chart sits between the summary and the DNA card, so the grid
    // is below the fold until scrolled into view.
    await tester.scrollUntilVisible(find.text('Earnings DNA'), 200);
    expect(find.text('Earnings DNA'), findsOneWidget);
    // Grades now appear both in the heatmap cells and in the ranked list.
    expect(find.text('A'), findsWidgets);
    expect(find.text('D'), findsWidgets);

    await tester.tap(find.text('Freedom'));
    await tester.pumpAndSettle();
    expect(find.text('Choose what driving is building'), findsOneWidget);
    expect(find.text('Money leaks'), findsOneWidget);

    await tester.tap(find.text('Create goal'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Emergency fund');
    await tester.enterText(fields.at(1), '5000');
    await tester.enterText(fields.at(2), '500');
    await tester.enterText(fields.at(3), '20');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save goal'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save goal'));
    await tester.pumpAndSettle();

    expect(find.text('Emergency fund'), findsOneWidget);
    expect(store.snapshot.freedomGoal?.targetAmount, 5000);

    await tester.tap(find.text('Coach'));
    await tester.pumpAndSettle();
    expect(find.text('Profit coach'), findsOneWidget);
    expect(find.text('Your next move'), findsOneWidget);
    expect(find.text('Emergency fund'), findsWidgets);
  });
}

List<Shift> _patternShifts() {
  final now = DateTime.now();
  return [
    _shift('a', now.subtract(const Duration(days: 1)), 7, 50),
    _shift('b', now.subtract(const Duration(days: 2)), 12, 40),
    _shift('c', now.subtract(const Duration(days: 3)), 18, 30),
    _shift('d', now.subtract(const Duration(days: 4)), 23, 20),
  ];
}

Shift _shift(String id, DateTime day, int hour, double profit) => Shift(
  id: id,
  platform: WorkPlatform.uber,
  gross: profit,
  hours: 1,
  miles: 0,
  directExpenses: 0,
  vehicleCostPerMile: 0,
  completedAt: DateTime(day.year, day.month, day.day, hour),
);
