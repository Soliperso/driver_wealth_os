import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a manual shift defaults to today but can be dated to the past', (
    tester,
  ) async {
    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter a session manually'));
    await tester.pumpAndSettle();

    // Defaults to today so the common case stays a single tap.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('shift-date-field')),
        matching: find.textContaining('Today'),
      ),
      findsOneWidget,
    );

    final target = DateTime.now().subtract(const Duration(days: 30));
    await tester.tap(find.byKey(const ValueKey('shift-date-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '${target.month.toString().padLeft(2, '0')}/'
      '${target.day.toString().padLeft(2, '0')}/'
      '${target.year}',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '300');
    await tester.enterText(fields.at(1), '8');
    await tester.enterText(fields.at(2), '100');
    await tester.enterText(fields.at(3), '20');
    await tester.enterText(fields.at(4), '.30');
    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    // The regression this guards: completedAt used to be DateTime.now() at
    // save time, so every manual shift was graded under the day and hour it
    // was typed rather than the one it was driven.
    final saved = store.snapshot.shifts.single;
    expect(saved.completedAt.year, target.year);
    expect(saved.completedAt.month, target.month);
    expect(saved.completedAt.day, target.day);
  });

  test('shifts are graded under the weekday they were driven', () {
    // Four distinct patterns are required before relative grades are assigned.
    final patterns = ShiftAnalytics.earningsPatterns([
      _shift('tue-evening', DateTime(2026, 3, 3, 19), 120),
      _shift('wed-morning', DateTime(2026, 3, 4, 8), 90),
      _shift('thu-midday', DateTime(2026, 3, 5, 13), 60),
      _shift('fri-latenight', DateTime(2026, 3, 6, 23), 30),
    ]);

    final tuesday = patterns.firstWhere(
      (pattern) => pattern.label.startsWith('Tuesday'),
    );
    expect(tuesday.timeBlock, TimeBlock.evening);
    expect(tuesday.grade, PatternGrade.a);
    expect(patterns.map((pattern) => pattern.label), hasLength(4));
  });
}

Shift _shift(String id, DateTime completedAt, double gross) => Shift.single(
  id: id,
  platform: WorkPlatform.uber,
  gross: gross,
  hours: 1,
  miles: 0,
  directExpenses: 0,
  vehicleCostPerMile: 0,
  completedAt: completedAt,
);
