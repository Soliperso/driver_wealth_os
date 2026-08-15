import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates true shift profitability', () {
    final shift = Shift.single(
      id: 'shift-1',
      platform: WorkPlatform.uber,
      gross: 300,
      hours: 8,
      miles: 100,
      directExpenses: 20,
      vehicleCostPerMile: .30,
      completedAt: DateTime(2026),
    );

    expect(shift.vehicleCost, 30);
    expect(shift.totalExpenses, 50);
    expect(shift.netProfit, 250);
    expect(shift.netPerHour, 31.25);
    expect(shift.netPerMile, 2.5);
    expect(shift.keepRate, closeTo(.8333, .0001));
  });

  test('rounds monetary results to cents', () {
    final shift = Shift.single(
      id: 'shift-rounding',
      platform: WorkPlatform.lyft,
      gross: 100,
      hours: 3,
      miles: 13.33,
      directExpenses: 10.01,
      vehicleCostPerMile: .27,
      completedAt: DateTime(2026),
    );

    expect(shift.vehicleCost, 3.60);
    expect(shift.totalExpenses, 13.61);
    expect(shift.netProfit, 86.39);
  });

  test('summary counts a shift id only once', () {
    final shift = Shift.single(
      id: 'same-source-record',
      platform: WorkPlatform.doorDash,
      gross: 200,
      hours: 5,
      miles: 50,
      directExpenses: 10,
      vehicleCostPerMile: .20,
      completedAt: DateTime(2026),
    );

    final summary = ShiftSummary.from([shift, shift]);

    expect(summary.shiftCount, 1);
    expect(summary.gross, 200);
    expect(summary.netProfit, 180);
    expect(summary.netPerHour, 36);
  });
}
