import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/coach/domain/coach_engine.dart';
import 'package:driver_wealth_os/features/freedom/domain/freedom_goal.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime(2026, 8, 1);

  test('freedom goal allocates positive profit once per unique shift', () {
    final goal = FreedomGoal(
      id: 'goal-1',
      title: 'Emergency fund',
      targetAmount: 1000,
      startingAmount: 100,
      allocationRate: .5,
      createdAt: createdAt,
    );
    final dayOne = _shift('day-one', DateTime(2026, 8, 3), 100);
    final dayTwo = _shift('day-two', DateTime(2026, 8, 4), 100);
    final beforeGoal = _shift('before', DateTime(2026, 7, 31), 500);

    final progress = goal.progress([
      dayOne,
      dayOne,
      dayTwo,
      beforeGoal,
    ], now: DateTime(2026, 8, 5));

    expect(progress.allocatedProfit, 100);
    expect(progress.amount, 200);
    expect(progress.remaining, 800);
    expect(progress.activeDays, 2);
    expect(progress.weeklyAllocation, 350);
    expect(progress.projectedWeeks, closeTo(800 / 350, .0001));
  });

  test('freedom goal round-trips through JSON', () {
    final goal = FreedomGoal(
      id: 'goal-json',
      title: 'Replace vehicle',
      targetAmount: 15000,
      startingAmount: 1200,
      allocationRate: .25,
      createdAt: createdAt,
    );

    final restored = FreedomGoal.fromJson(goal.toJson());

    expect(restored.id, goal.id);
    expect(restored.title, goal.title);
    expect(restored.targetAmount, goal.targetAmount);
    expect(restored.startingAmount, goal.startingAmount);
    expect(restored.allocationRate, goal.allocationRate);
    expect(restored.createdAt, goal.createdAt);
  });

  test('coach uses saved data and does not duplicate its priority insight', () {
    final current = DateTime(2026, 8, 11, 18);
    final insights = CoachEngine.build(
      shifts: [_shift('today', current, 305), _shift('today', current, 305)],
      dailyGoal: 300,
      now: current,
    );

    expect(insights.first.title, 'Today’s goal is complete');
    expect(
      insights.where((insight) => insight.title == 'Today’s goal is complete'),
      hasLength(1),
    );
    expect(insights.first.message, contains(r'$305.00'));
  });

  test('coach gives an honest starter state without shift data', () {
    final insights = CoachEngine.build(shifts: const [], dailyGoal: 250);

    expect(insights, hasLength(1));
    expect(insights.single.kind, CoachInsightKind.start);
  });
}

Shift _shift(String id, DateTime date, double profit) => Shift(
  id: id,
  platform: WorkPlatform.uber,
  gross: profit,
  hours: 5,
  miles: 0,
  directExpenses: 0,
  vehicleCostPerMile: 0,
  completedAt: date,
);
