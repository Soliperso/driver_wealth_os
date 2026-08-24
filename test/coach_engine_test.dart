import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/coach/domain/coach_engine.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    // The figure moved out of the sentence and into the headline the screen
    // renders it as, so that a tile and a sentence stop saying the same thing.
    // Still the same assertion: the number comes from the saved shift.
    expect(insights.first.headline?.value, 305);
    expect(insights.first.headline?.text, r'$305.00');
    expect(insights.first.headline?.heroLabel, 'Kept today');
  });

  test('coach gives an honest starter state without shift data', () {
    final insights = CoachEngine.build(shifts: const [], dailyGoal: 250);

    expect(insights, hasLength(1));
    expect(insights.single.kind, CoachInsightKind.start);
  });

  test('dashboard unlocks best times only from distinct reviewed patterns', () {
    final current = DateTime(2026, 8, 20, 12);
    final dashboard = CoachEngine.dashboard(
      shifts: [
        _timedShift('a', DateTime(2026, 8, 17, 7), miles: 20),
        _timedShift('b', DateTime(2026, 8, 18, 12), miles: 30),
        _timedShift('c', DateTime(2026, 8, 19, 18), miles: 25),
        _timedShift('d', DateTime(2026, 8, 20, 23), miles: 15),
      ],
      dailyGoal: 250,
      hourlyFloor: 25,
      now: current,
    );

    expect(dashboard.canOpenBestTimes, isTrue);
    expect(dashboard.patterns, hasLength(4));
    expect(dashboard.weekly.kind, CoachInsightKind.weekly);
    expect(dashboard.opportunity.isReady, isTrue);
    expect(dashboard.cost.isReady, isTrue);
    expect(dashboard.questions, isNotEmpty);
  });

  test(
    'dashboard shows learning states instead of unsupported conclusions',
    () {
      final dashboard = CoachEngine.dashboard(
        shifts: [_shift('one', DateTime(2026, 8, 20), 100)],
        dailyGoal: 250,
        now: DateTime(2026, 8, 20),
      );

      expect(dashboard.canOpenBestTimes, isFalse);
      expect(dashboard.opportunity.isReady, isFalse);
      expect(dashboard.leak.isReady, isFalse);
      expect(dashboard.cost.isReady, isFalse);
    },
  );
}

Shift _shift(String id, DateTime date, double profit) => Shift.single(
  id: id,
  platform: WorkPlatform.uber,
  gross: profit,
  hours: 5,
  miles: 0,
  directExpenses: 0,
  vehicleCostPerMile: 0,
  completedAt: date,
);

Shift _timedShift(String id, DateTime date, {required double miles}) =>
    Shift.single(
      id: id,
      platform: WorkPlatform.uber,
      gross: 180,
      hours: 5,
      miles: miles,
      directExpenses: 10,
      vehicleCostPerMile: .30,
      completedAt: date,
    );
