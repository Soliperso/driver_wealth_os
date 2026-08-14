import 'shift.dart';
import 'shift_summary.dart';

class ShiftAnalytics {
  const ShiftAnalytics._();

  static WeeklyPerformance weekly(Iterable<Shift> shifts, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final previousStart = weekStart.subtract(const Duration(days: 7));
    final unique = _unique(shifts);
    final currentShifts = unique
        .where(
          (shift) =>
              !shift.completedAt.isBefore(weekStart) &&
              shift.completedAt.isBefore(
                weekStart.add(const Duration(days: 7)),
              ),
        )
        .toList();
    final previousShifts = unique
        .where(
          (shift) =>
              !shift.completedAt.isBefore(previousStart) &&
              shift.completedAt.isBefore(weekStart),
        )
        .toList();
    final summary = ShiftSummary.from(currentShifts);
    final previousSummary = ShiftSummary.from(previousShifts);
    final ranked = currentShifts.where((shift) => shift.hours > 0).toList()
      ..sort((a, b) => b.netPerHour.compareTo(a.netPerHour));
    // A percentage is only meaningful against a profitable baseline. Dividing
    // by the absolute value of a loss reports recovering from −$100 to +$50 as
    // "+150%", which reads like a strong week rather than a small one. When
    // last week lost money there is no honest ratio, so the badge falls back
    // to the dollar difference.
    final change = previousSummary.netProfit > 0
        ? (summary.netProfit - previousSummary.netProfit) /
              previousSummary.netProfit
        : null;
    final delta = previousShifts.isEmpty
        ? null
        : _currency(summary.netProfit - previousSummary.netProfit);
    return WeeklyPerformance(
      weekStart: weekStart,
      summary: summary,
      previousSummary: previousSummary,
      netProfitChange: change,
      netProfitDelta: delta,
      bestShift: ranked.isEmpty ? null : ranked.first,
      weakestShift: ranked.isEmpty ? null : ranked.last,
      dailyNetProfit: _dailyNetProfit(currentShifts, weekStart),
      previousDailyNetProfit: _dailyNetProfit(previousShifts, previousStart),
    );
  }

  /// Seven totals, Monday first, so a week can be charted day by day.
  static List<double> _dailyNetProfit(List<Shift> shifts, DateTime weekStart) {
    final totals = List<double>.filled(7, 0);
    for (final shift in shifts) {
      final index = shift.completedAt.difference(weekStart).inDays;
      if (index < 0 || index > 6) continue;
      totals[index] += shift.netProfit;
    }
    return [for (final total in totals) _currency(total)];
  }

  static List<EarningsPattern> earningsPatterns(Iterable<Shift> shifts) {
    final groups = <String, List<Shift>>{};
    for (final shift in _unique(shifts).where((shift) => shift.hours > 0)) {
      final block = TimeBlock.fromHour(shift.completedAt.hour);
      final key = '${shift.completedAt.weekday}-${block.name}';
      groups.putIfAbsent(key, () => []).add(shift);
    }
    final patterns = groups.values.map((group) {
      final summary = ShiftSummary.from(group);
      final first = group.first;
      return EarningsPattern(
        weekday: first.completedAt.weekday,
        timeBlock: TimeBlock.fromHour(first.completedAt.hour),
        shiftCount: summary.shiftCount,
        netProfit: summary.netProfit,
        hours: summary.hours,
        netPerHour: summary.netPerHour,
        grade: PatternGrade.pending,
      );
    }).toList()..sort((a, b) => b.netPerHour.compareTo(a.netPerHour));

    if (patterns.length < 4) return patterns;
    return [
      for (var index = 0; index < patterns.length; index++)
        patterns[index].withGrade(_grade(index, patterns.length)),
    ];
  }

  static List<MoneyLeak> moneyLeaks(Iterable<Shift> shifts) {
    final unique = _unique(shifts).where((shift) => shift.hours > 0).toList();
    if (unique.isEmpty) return const [];
    final total = ShiftSummary.from(unique);
    final baselineRate = total.netPerHour;
    final leaks = <MoneyLeak>[];
    for (final shift in unique) {
      final candidates = <MoneyLeak>[];
      if (shift.netProfit < 0) {
        candidates.add(
          MoneyLeak(
            shiftId: shift.id,
            type: MoneyLeakType.negativeProfit,
            title: 'Unprofitable shift',
            detail:
                '${shift.platform.displayName} lost \$${shift.netProfit.abs().toStringAsFixed(2)} after costs.',
            potentialRecovery: shift.netProfit.abs(),
          ),
        );
      }
      if (baselineRate > 0 && shift.netPerHour < baselineRate * .75) {
        final recovery = ((baselineRate - shift.netPerHour) * shift.hours)
            .clamp(0, double.infinity)
            .toDouble();
        candidates.add(
          MoneyLeak(
            shiftId: shift.id,
            type: MoneyLeakType.lowHourlyProfit,
            title: 'Low-profit hours',
            // A shift that lost money is not "139% below average" — nothing can
            // be more than 100% below. Say what actually happened instead.
            detail: shift.netPerHour < 0
                ? '${shift.platform.displayName} cost more per hour than it paid.'
                : '${shift.platform.displayName} ran '
                      '${_percentBelow(shift.netPerHour, baselineRate)} below '
                      'your tracked hourly average.',
            potentialRecovery: recovery,
          ),
        );
      }
      if (shift.gross > 0 && shift.keepRate < .65) {
        final recovery = (.65 * shift.gross - shift.netProfit)
            .clamp(0, double.infinity)
            .toDouble();
        candidates.add(
          MoneyLeak(
            shiftId: shift.id,
            type: MoneyLeakType.lowKeepRate,
            title: 'Low keep rate',
            detail:
                '${shift.platform.displayName} kept ${(shift.keepRate * 100).toStringAsFixed(0)}% after costs.',
            potentialRecovery: recovery,
          ),
        );
      }
      if (candidates.isNotEmpty) {
        candidates.sort(
          (a, b) => b.potentialRecovery.compareTo(a.potentialRecovery),
        );
        leaks.add(candidates.first);
      }
    }
    leaks.sort((a, b) => b.potentialRecovery.compareTo(a.potentialRecovery));
    return leaks;
  }

  static double totalPotentialRecovery(Iterable<MoneyLeak> leaks) =>
      _currency(leaks.fold(0.0, (sum, leak) => sum + leak.potentialRecovery));

  static List<Shift> _unique(Iterable<Shift> shifts) {
    final unique = <String, Shift>{};
    for (final shift in shifts) {
      unique.putIfAbsent(shift.id, () => shift);
    }
    return unique.values.toList();
  }

  static PatternGrade _grade(int index, int count) {
    final percentile = index / count;
    if (percentile < .25) return PatternGrade.a;
    if (percentile < .50) return PatternGrade.b;
    if (percentile < .75) return PatternGrade.c;
    return PatternGrade.d;
  }

  static String _percentBelow(double value, double baseline) =>
      '${(((1 - value / baseline) * 100).round()).clamp(0, 99)}%';

  static double _currency(num value) => (value * 100).round() / 100;
}

class WeeklyPerformance {
  const WeeklyPerformance({
    required this.weekStart,
    required this.summary,
    required this.previousSummary,
    required this.netProfitChange,
    required this.bestShift,
    required this.weakestShift,
    this.netProfitDelta,
    this.dailyNetProfit = const [0, 0, 0, 0, 0, 0, 0],
    this.previousDailyNetProfit = const [0, 0, 0, 0, 0, 0, 0],
  });

  final DateTime weekStart;
  final ShiftSummary summary;
  final ShiftSummary previousSummary;
  /// Week-over-week change as a ratio. Null unless the prior week turned a
  /// profit, because a percentage against zero or a loss says nothing.
  final double? netProfitChange;

  /// Week-over-week change in dollars. Null only when there was no prior week
  /// to compare against. Always meaningful, unlike [netProfitChange].
  final double? netProfitDelta;

  final Shift? bestShift;
  final Shift? weakestShift;

  /// Monday-first daily totals for the current and prior week.
  final List<double> dailyNetProfit;
  final List<double> previousDailyNetProfit;
}

enum PatternGrade { pending, a, b, c, d }

enum TimeBlock {
  earlyMorning('Early morning', '12–6 AM'),
  morning('Morning', '6–11 AM'),
  midday('Midday', '11 AM–4 PM'),
  evening('Evening', '4–10 PM'),
  lateNight('Late night', '10 PM–12 AM');

  const TimeBlock(this.label, this.range);

  final String label;
  final String range;

  static TimeBlock fromHour(int hour) {
    if (hour < 6) return earlyMorning;
    if (hour < 11) return morning;
    if (hour < 16) return midday;
    if (hour < 22) return evening;
    return lateNight;
  }
}

class EarningsPattern {
  const EarningsPattern({
    required this.weekday,
    required this.timeBlock,
    required this.shiftCount,
    required this.netProfit,
    required this.hours,
    required this.netPerHour,
    required this.grade,
  });

  final int weekday;
  final TimeBlock timeBlock;
  final int shiftCount;
  final double netProfit;
  final double hours;
  final double netPerHour;
  final PatternGrade grade;

  String get label => '${_weekday(weekday)} ${timeBlock.label.toLowerCase()}';

  EarningsPattern withGrade(PatternGrade value) => EarningsPattern(
    weekday: weekday,
    timeBlock: timeBlock,
    shiftCount: shiftCount,
    netProfit: netProfit,
    hours: hours,
    netPerHour: netPerHour,
    grade: value,
  );

  static String _weekday(int weekday) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];
}

enum MoneyLeakType { negativeProfit, lowHourlyProfit, lowKeepRate }

class MoneyLeak {
  const MoneyLeak({
    required this.shiftId,
    required this.type,
    required this.title,
    required this.detail,
    required this.potentialRecovery,
  });

  final String shiftId;
  final MoneyLeakType type;
  final String title;
  final String detail;
  final double potentialRecovery;
}
