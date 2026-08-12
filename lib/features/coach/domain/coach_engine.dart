import '../../freedom/domain/freedom_goal.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_analytics.dart';
import '../../shifts/domain/shift_summary.dart';

class CoachEngine {
  const CoachEngine._();

  static List<CoachInsight> build({
    required Iterable<Shift> shifts,
    required double dailyGoal,
    FreedomGoal? freedomGoal,
    DateTime? now,
  }) {
    final unique = <String, Shift>{};
    for (final shift in shifts) {
      unique.putIfAbsent(shift.id, () => shift);
    }
    if (unique.isEmpty) {
      return const [
        CoachInsight(
          title: 'Add your first completed shift',
          message:
              'Your coach needs earnings, hours, mileage and costs before it can compare profitable patterns.',
          kind: CoachInsightKind.start,
        ),
      ];
    }

    final current = now ?? DateTime.now();
    final today = ShiftSummary.from(
      unique.values.where((shift) => shift.occurredOn(current)),
    );
    final weekly = ShiftAnalytics.weekly(unique.values, now: current);
    final patterns = ShiftAnalytics.earningsPatterns(unique.values);
    final leaks = ShiftAnalytics.moneyLeaks(unique.values);
    final insights = <CoachInsight>[];

    if (today.shiftCount > 0) {
      if (today.netProfit >= dailyGoal) {
        insights.add(
          CoachInsight(
            title: 'Today’s goal is complete',
            message:
                'You kept \$${today.netProfit.toStringAsFixed(2)}, reaching your \$${dailyGoal.toStringAsFixed(0)} target. Compare another hour against your \$${today.netPerHour.toStringAsFixed(2)} current pace before continuing.',
            kind: CoachInsightKind.goal,
          ),
        );
      } else {
        insights.add(
          CoachInsight(
            title: 'Close today’s profit gap',
            message:
                'You are \$${(dailyGoal - today.netProfit).toStringAsFixed(2)} from today’s goal. Your tracked pace is \$${today.netPerHour.toStringAsFixed(2)} net per hour.',
            kind: CoachInsightKind.goal,
          ),
        );
      }
    }

    if (leaks.isNotEmpty) {
      final leak = leaks.first;
      insights.add(
        CoachInsight(
          title: leak.title,
          message:
              '${leak.detail} Review this shift first; its estimated gap is \$${leak.potentialRecovery.toStringAsFixed(2)}.',
          kind: CoachInsightKind.leak,
        ),
      );
    }

    final graded = patterns.where(
      (pattern) => pattern.grade != PatternGrade.pending,
    );
    if (graded.isNotEmpty) {
      final best = graded.first;
      insights.add(
        CoachInsight(
          title: 'Protect your strongest pattern',
          message:
              '${best.label} is currently A-tier at \$${best.netPerHour.toStringAsFixed(2)} net per hour across ${best.shiftCount} ${best.shiftCount == 1 ? 'shift' : 'shifts'}.',
          kind: CoachInsightKind.pattern,
        ),
      );
    } else if (patterns.isNotEmpty) {
      insights.add(
        CoachInsight(
          title: 'Build your Earnings DNA',
          message:
              'You have ${patterns.length} of 4 distinct day-and-time patterns needed for reliable relative grades.',
          kind: CoachInsightKind.pattern,
        ),
      );
    }

    if (freedomGoal != null) {
      final progress = freedomGoal.progress(unique.values, now: current);
      insights.add(
        CoachInsight(
          title: freedomGoal.title,
          message:
              '\$${progress.amount.toStringAsFixed(2)} of \$${freedomGoal.targetAmount.toStringAsFixed(2)} is tracked. ${(freedomGoal.allocationRate * 100).toStringAsFixed(0)}% of positive profit is allocated to this goal.',
          kind: CoachInsightKind.freedom,
        ),
      );
    }

    if (weekly.summary.shiftCount > 0 && insights.length < 4) {
      insights.add(
        CoachInsight(
          title: 'This week at a glance',
          message:
              '${weekly.summary.shiftCount} shifts produced \$${weekly.summary.netProfit.toStringAsFixed(2)} true profit at \$${weekly.summary.netPerHour.toStringAsFixed(2)} per hour.',
          kind: CoachInsightKind.weekly,
        ),
      );
    }
    return insights.take(4).toList();
  }
}

enum CoachInsightKind { start, goal, leak, pattern, freedom, weekly }

class CoachInsight {
  const CoachInsight({
    required this.title,
    required this.message,
    required this.kind,
  });

  final String title;
  final String message;
  final CoachInsightKind kind;
}
