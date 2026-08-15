import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('one shift keeps every History insight discoverable', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [_shift(id: 'current')],
      ),
    );

    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Profit by day'), 200);
    expect(find.text('Profit by day'), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-style-bars')), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-style-line')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chart-style-line')));
    await tester.pumpAndSettle();
    expect(find.text('Tap a point for its full numbers.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Platform comparison'), 200);
    expect(
      find.byKey(const ValueKey('platform-comparison-learning')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Earnings DNA'), 200);
    expect(find.text('Earnings DNA'), findsOneWidget);
    expect(find.text('1 of 4 patterns tracked'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Shifts this week'), 200);
    expect(find.text('Shifts this week'), findsOneWidget);
    expect(find.textContaining('All time'), findsNothing);
  });

  testWidgets('the shift list follows the period until View all is chosen', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [
          _shift(id: 'current'),
          _shift(
            id: 'older',
            completedAt: DateTime.now().subtract(const Duration(days: 40)),
          ),
        ],
      ),
    );

    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('history-shift-current')),
      200,
    );
    expect(find.byKey(const ValueKey('history-shift-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-shift-older')), findsNothing);
    await tester.scrollUntilVisible(find.text('View all shifts'), 200);
    await tester.tap(find.text('View all shifts'));
    await tester.pumpAndSettle();

    expect(find.text('All shifts'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-shift-older')), findsOneWidget);
  });

  testWidgets('an unreviewed import gets one compact cost warning', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [
          _shift(
            id: 'imported',
            source: ShiftSource.imported,
            costsReviewed: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cost-review-notice')), findsOneWidget);
    expect(find.text('Review costs for 1 imported shift'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-imported-costs')));
    await tester.pumpAndSettle();
    expect(find.text('Shift details'), findsOneWidget);
  });

  testWidgets('platform comparison waits for two reviewed shifts each', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [
          _shift(id: 'uber-1'),
          _shift(id: 'uber-2'),
          _shift(id: 'lyft-1', platform: WorkPlatform.lyft),
          _shift(id: 'lyft-2', platform: WorkPlatform.lyft),
        ],
      ),
    );

    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Platform comparison'), 200);
    expect(find.text('Platform comparison'), findsOneWidget);
    expect(
      find.text('Based on reviewed costs and at least 2 shifts each.'),
      findsOneWidget,
    );
    // Four shifts at one day/time are still one distinct earning pattern, so
    // the section stays visible and accurately shows that it is learning.
    await tester.scrollUntilVisible(find.text('Earnings DNA'), 200);
    expect(find.text('Earnings DNA'), findsOneWidget);
    expect(find.text('1 of 4 patterns tracked'), findsOneWidget);
  });

  test('old imported records migrate into cost review safely', () {
    final json = _shift(id: 'legacy', source: ShiftSource.imported).toJson()
      ..remove('costsReviewed');

    final restored = Shift.fromJson(json);

    expect(restored.costsReviewed, isFalse);
    expect(restored.copyWith(costsReviewed: true).costsReviewed, isTrue);
  });
}

Shift _shift({
  required String id,
  DateTime? completedAt,
  WorkPlatform platform = WorkPlatform.uber,
  ShiftSource source = ShiftSource.manual,
  bool costsReviewed = true,
}) => Shift.single(
  id: id,
  platform: platform,
  gross: 120,
  hours: 2,
  miles: 20,
  directExpenses: 10,
  vehicleCostPerMile: .20,
  completedAt:
      completedAt ??
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
  source: source,
  costsReviewed: costsReviewed,
);
