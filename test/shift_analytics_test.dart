import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'weekly performance uses Monday through Sunday and deduplicates ids',
    () {
      final currentA = _shift(
        id: 'current-a',
        date: DateTime(2026, 8, 10, 8),
        gross: 100,
        hours: 4,
        directExpenses: 10,
        miles: 50,
        vehicleRate: .20,
      );
      final currentB = _shift(
        id: 'current-b',
        date: DateTime(2026, 8, 11, 18),
        gross: 200,
        hours: 5,
        directExpenses: 20,
        miles: 100,
        vehicleRate: .20,
      );
      final previous = _shift(
        id: 'previous',
        date: DateTime(2026, 8, 3, 9),
        gross: 200,
        hours: 5,
        directExpenses: 20,
        miles: 100,
        vehicleRate: .20,
      );

      final result = ShiftAnalytics.weekly([
        currentA,
        currentA,
        currentB,
        previous,
      ], now: DateTime(2026, 8, 12));

      expect(result.weekStart, DateTime(2026, 8, 10));
      expect(result.summary.shiftCount, 2);
      expect(result.summary.netProfit, 240);
      expect(result.previousSummary.netProfit, 160);
      expect(result.netProfitChange, .5);
      expect(result.bestShift?.id, 'current-b');
      expect(result.weakestShift?.id, 'current-a');
    },
  );

  test('Earnings DNA assigns relative grades to four distinct patterns', () {
    final patterns = ShiftAnalytics.earningsPatterns([
      _profitShift('a', DateTime(2026, 8, 10, 7), 40),
      _profitShift('b', DateTime(2026, 8, 11, 12), 30),
      _profitShift('c', DateTime(2026, 8, 12, 18), 20),
      _profitShift('d', DateTime(2026, 8, 13, 23), 10),
    ]);

    expect(patterns.map((pattern) => pattern.grade), [
      PatternGrade.a,
      PatternGrade.b,
      PatternGrade.c,
      PatternGrade.d,
    ]);
    expect(patterns.map((pattern) => pattern.netPerHour), [40, 30, 20, 10]);
  });

  test('money leaks reports at most one recovery estimate per shift id', () {
    final strong = _profitShift('strong', DateTime(2026, 8, 10, 7), 90);
    final weak = _shift(
      id: 'weak',
      date: DateTime(2026, 8, 11, 12),
      gross: 100,
      hours: 4,
      directExpenses: 80,
      miles: 0,
      vehicleRate: 0,
    );

    final leaks = ShiftAnalytics.moneyLeaks([strong, weak, weak]);

    expect(leaks.where((leak) => leak.shiftId == 'weak'), hasLength(1));
    expect(leaks.map((leak) => leak.shiftId).toSet().length, leaks.length);
    expect(
      ShiftAnalytics.totalPotentialRecovery(leaks),
      leaks.fold<double>(0, (sum, leak) => sum + leak.potentialRecovery),
    );
  });

  test('a losing prior week reports dollars, not a flattering percentage', () {
    // Last week lost $100, this week made $50. Dividing by the absolute value
    // of the loss would render "+150%", which reads like a blowout week.
    final previous = _shift(
      id: 'previous',
      date: DateTime(2026, 8, 3, 9),
      gross: 0,
      hours: 5,
      directExpenses: 100,
      miles: 0,
      vehicleRate: 0,
    );
    final current = _shift(
      id: 'current',
      date: DateTime(2026, 8, 10, 9),
      gross: 50,
      hours: 5,
      directExpenses: 0,
      miles: 0,
      vehicleRate: 0,
    );

    final result = ShiftAnalytics.weekly([
      previous,
      current,
    ], now: DateTime(2026, 8, 12));

    expect(result.previousSummary.netProfit, -100);
    expect(result.summary.netProfit, 50);
    // No ratio is honest against a loss, so none is offered.
    expect(result.netProfitChange, isNull);
    expect(result.netProfitDelta, 150);
  });

  test('a break-even prior week still reports a dollar change', () {
    final previous = _shift(
      id: 'previous',
      date: DateTime(2026, 8, 3, 9),
      gross: 100,
      hours: 5,
      directExpenses: 100,
      miles: 0,
      vehicleRate: 0,
    );
    final current = _shift(
      id: 'current',
      date: DateTime(2026, 8, 10, 9),
      gross: 80,
      hours: 5,
      directExpenses: 0,
      miles: 0,
      vehicleRate: 0,
    );

    final result = ShiftAnalytics.weekly([
      previous,
      current,
    ], now: DateTime(2026, 8, 12));

    // Dividing by zero would have produced infinity.
    expect(result.previousSummary.netProfit, 0);
    expect(result.netProfitChange, isNull);
    expect(result.netProfitDelta, 80);
  });

  test('no prior week means nothing to compare against', () {
    final current = _shift(
      id: 'current',
      date: DateTime(2026, 8, 10, 9),
      gross: 80,
      hours: 5,
      directExpenses: 0,
      miles: 0,
      vehicleRate: 0,
    );

    final result = ShiftAnalytics.weekly([current], now: DateTime(2026, 8, 12));

    expect(result.netProfitChange, isNull);
    // A first week is not an $80 improvement on anything.
    expect(result.netProfitDelta, isNull);
  });
}

Shift _profitShift(String id, DateTime date, double profitPerHour) => _shift(
  id: id,
  date: date,
  gross: profitPerHour,
  hours: 1,
  directExpenses: 0,
  miles: 0,
  vehicleRate: 0,
);

Shift _shift({
  required String id,
  required DateTime date,
  required double gross,
  required double hours,
  required double directExpenses,
  required double miles,
  required double vehicleRate,
}) => Shift(
  id: id,
  platform: WorkPlatform.uber,
  gross: gross,
  hours: hours,
  miles: miles,
  directExpenses: directExpenses,
  vehicleCostPerMile: vehicleRate,
  completedAt: date,
);
