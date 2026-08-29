import 'package:intl/intl.dart';

import '../../accounts/domain/work_platform.dart';
import 'shift.dart';
import 'shift_summary.dart';

/// The window History is reporting on.
///
/// [ShiftAnalytics.weekly] answers one fixed question — "how is this week
/// going?" — and stays for the Coach engine, which only ever asks that. This
/// generalises the same shape so the driver can also ask about a day, a month
/// or a year without four near-identical aggregators.
enum ReportPeriod {
  day('D', 'Day'),
  week('W', 'Week'),
  month('M', 'Month'),
  year('Y', 'Year');

  const ReportPeriod(this.shortLabel, this.label);

  final String shortLabel;
  final String label;
}

/// A half-open window: [start] inclusive, [end] exclusive.
///
/// All stepping is calendar arithmetic rather than `Duration(days: n)`, because
/// adding 24 hours across a daylight-saving boundary lands on the wrong day.
class PeriodRange {
  const PeriodRange({
    required this.start,
    required this.end,
    required this.period,
  });

  final DateTime start;
  final DateTime end;
  final ReportPeriod period;

  factory PeriodRange.containing(DateTime anchor, ReportPeriod period) {
    final day = DateTime(anchor.year, anchor.month, anchor.day);
    return switch (period) {
      ReportPeriod.day => PeriodRange(
        start: day,
        end: DateTime(day.year, day.month, day.day + 1),
        period: period,
      ),
      ReportPeriod.week => () {
        final monday = DateTime(
          day.year,
          day.month,
          day.day - (day.weekday - 1),
        );
        return PeriodRange(
          start: monday,
          end: DateTime(monday.year, monday.month, monday.day + 7),
          period: period,
        );
      }(),
      ReportPeriod.month => PeriodRange(
        start: DateTime(day.year, day.month),
        // Month 13 normalises to January of the next year.
        end: DateTime(day.year, day.month + 1),
        period: period,
      ),
      ReportPeriod.year => PeriodRange(
        start: DateTime(day.year),
        end: DateTime(day.year + 1),
        period: period,
      ),
    };
  }

  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  PeriodRange previous() => PeriodRange.containing(switch (period) {
    ReportPeriod.day => DateTime(start.year, start.month, start.day - 1),
    ReportPeriod.week => DateTime(start.year, start.month, start.day - 7),
    ReportPeriod.month => DateTime(start.year, start.month - 1),
    ReportPeriod.year => DateTime(start.year - 1),
  }, period);

  PeriodRange next() => PeriodRange.containing(switch (period) {
    ReportPeriod.day => DateTime(start.year, start.month, start.day + 1),
    ReportPeriod.week => DateTime(start.year, start.month, start.day + 7),
    ReportPeriod.month => DateTime(start.year, start.month + 1),
    ReportPeriod.year => DateTime(start.year + 1),
  }, period);

  /// True when [now] falls inside this window, so the UI can disable stepping
  /// forward past the present and label the window "Today"/"This week".
  bool isCurrent(DateTime now) => contains(now);

  String label(DateTime now) {
    final current = isCurrent(now);
    switch (period) {
      case ReportPeriod.day:
        if (current) return 'Today';
        final sameYear = start.year == now.year;
        return DateFormat(
          sameYear ? 'EEEE, MMM d' : 'EEE, MMM d, y',
          _locale,
        ).format(start);
      case ReportPeriod.week:
        if (current) return 'This week';
        final last = DateTime(start.year, start.month, start.day + 6);
        final from = DateFormat('MMM d', _locale).format(start);
        // "Jul 28 – Aug 3" needs the month twice; "Aug 11–17" does not.
        final to = DateFormat(
          last.month == start.month ? 'd' : 'MMM d',
          _locale,
        ).format(last);
        final year = start.year == now.year ? '' : ', ${start.year}';
        return '$from–$to$year';
      case ReportPeriod.month:
        if (current) return 'This month';
        return DateFormat(
          start.year == now.year ? 'MMMM' : 'MMMM y',
          _locale,
        ).format(start);
      case ReportPeriod.year:
        return current ? 'This year' : '${start.year}';
    }
  }

  /// The window in plain words, for the empty state and screen readers, where
  /// "This month" alone is too vague to be useful.
  String get plainLabel => switch (period) {
    ReportPeriod.day => DateFormat('EEEE, MMM d', _locale).format(start),
    ReportPeriod.week =>
      '${DateFormat('MMM d', _locale).format(start)} – '
          '${DateFormat('MMM d', _locale).format(DateTime(start.year, start.month, start.day + 6))}',
    ReportPeriod.month => DateFormat('MMMM y', _locale).format(start),
    ReportPeriod.year => '${start.year}',
  };

  static const _locale = 'en_US';

  @override
  bool operator ==(Object other) =>
      other is PeriodRange &&
      other.start == start &&
      other.end == end &&
      other.period == period;

  @override
  int get hashCode => Object.hash(start, end, period);
}

/// One bar. Carries its own summary so the detail panel can show every figure
/// without going back to the shift list.
class ProfitBucket {
  const ProfitBucket({
    required this.start,
    required this.label,
    required this.detailLabel,
    required this.summary,
    this.platform,
  });

  final DateTime start;

  /// The axis tick — a single letter or a day number.
  final String label;

  /// The panel heading, e.g. "Friday, Aug 14".
  final String detailLabel;

  final ShiftSummary summary;

  final WorkPlatform? platform;

  double get netProfit => summary.netProfit;
  int get shiftCount => summary.shiftCount;
}

class PeriodPerformance {
  const PeriodPerformance({
    required this.range,
    required this.summary,
    required this.previousSummary,
    required this.netProfitChange,
    required this.netProfitDelta,
    required this.buckets,
    required this.previousBuckets,
    required this.bestShift,
    required this.labelStride,
  });

  final PeriodRange range;
  final ShiftSummary summary;
  final ShiftSummary previousSummary;

  /// Change as a ratio. Null unless the prior period turned a profit, because a
  /// percentage against zero or a loss says nothing — recovering from −$100 to
  /// +$50 is not "+150%".
  final double? netProfitChange;

  /// Change in dollars. Null only when there was no prior period to compare
  /// against. Always meaningful, unlike [netProfitChange].
  final double? netProfitDelta;

  final List<ProfitBucket> buckets;

  /// Prior-period totals, index-aligned with [buckets] and truncated to the
  /// shorter of the two — February has 28 buckets where January has 31.
  final List<double> previousBuckets;

  final Shift? bestShift;

  /// Draw every nth axis label. A month's 31 ticks will not fit on a phone.
  final int labelStride;

  bool get isEmpty => summary.shiftCount == 0;
}

abstract final class PeriodAnalytics {
  static const _locale = 'en_US';

  static PeriodPerformance of(
    Iterable<Shift> shifts,
    ReportPeriod period,
    DateTime anchor,
  ) {
    final range = PeriodRange.containing(anchor, period);
    final previousRange = range.previous();
    final unique = _unique(shifts);

    final current = unique.where((s) => range.contains(s.completedAt)).toList()
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final previous =
        unique.where((s) => previousRange.contains(s.completedAt)).toList()
          ..sort((a, b) => a.completedAt.compareTo(b.completedAt));

    final summary = ShiftSummary.from(current);
    final previousSummary = ShiftSummary.from(previous);

    final ranked = current.where((s) => s.hours > 0).toList()
      ..sort((a, b) => b.netPerHour.compareTo(a.netPerHour));

    final buckets = _buckets(current, range);
    // A day's bars are individual sessions, so lining yesterday's third shift up
    // behind today's third shift compares nothing. No ghost bars there.
    final previousValues = period == ReportPeriod.day || previous.isEmpty
        ? const <double>[]
        : [for (final b in _buckets(previous, previousRange)) b.netProfit];

    return PeriodPerformance(
      range: range,
      summary: summary,
      previousSummary: previousSummary,
      netProfitChange: previousSummary.netProfit > 0
          ? (summary.netProfit - previousSummary.netProfit) /
                previousSummary.netProfit
          : null,
      netProfitDelta: previous.isEmpty
          ? null
          : _currency(summary.netProfit - previousSummary.netProfit),
      buckets: buckets,
      previousBuckets: previousValues.length > buckets.length
          ? previousValues.sublist(0, buckets.length)
          : previousValues,
      bestShift: ranked.isEmpty ? null : ranked.first,
      labelStride: period == ReportPeriod.month ? 7 : 1,
    );
  }

  static List<ProfitBucket> _buckets(List<Shift> shifts, PeriodRange range) =>
      switch (range.period) {
        ReportPeriod.day => _shiftBuckets(shifts),
        ReportPeriod.week => _calendarBuckets(shifts, range, 7),
        ReportPeriod.month => _calendarBuckets(
          shifts,
          range,
          _daysBetween(range.start, range.end),
        ),
        ReportPeriod.year => _monthBuckets(shifts, range),
      };

  /// One bar per shift, in the order they were completed.
  static List<ProfitBucket> _shiftBuckets(List<Shift> shifts) => [
    for (final shift in shifts)
      ProfitBucket(
        start: shift.completedAt,
        label: shift.platform.displayName.substring(0, 1),
        detailLabel:
            '${shift.platform.displayName} · '
            '${DateFormat('h:mm a', _locale).format(shift.completedAt)}',
        summary: ShiftSummary.from([shift]),
        platform: shift.platform,
      ),
  ];

  static List<ProfitBucket> _calendarBuckets(
    List<Shift> shifts,
    PeriodRange range,
    int dayCount,
  ) {
    final grouped = List.generate(dayCount, (_) => <Shift>[]);
    for (final shift in shifts) {
      final index = _daysBetween(range.start, shift.completedAt);
      if (index < 0 || index >= dayCount) continue;
      grouped[index].add(shift);
    }
    return [
      for (var i = 0; i < dayCount; i++)
        () {
          final day = DateTime(
            range.start.year,
            range.start.month,
            range.start.day + i,
          );
          return ProfitBucket(
            start: day,
            label: range.period == ReportPeriod.week
                ? _weekdayInitials[i]
                : '${day.day}',
            detailLabel: DateFormat('EEEE, MMM d', _locale).format(day),
            summary: ShiftSummary.from(grouped[i]),
          );
        }(),
    ];
  }

  static List<ProfitBucket> _monthBuckets(
    List<Shift> shifts,
    PeriodRange range,
  ) {
    final grouped = List.generate(12, (_) => <Shift>[]);
    for (final shift in shifts) {
      grouped[shift.completedAt.month - 1].add(shift);
    }
    return [
      for (var i = 0; i < 12; i++)
        () {
          final month = DateTime(range.start.year, i + 1);
          return ProfitBucket(
            start: month,
            label: _monthInitials[i],
            detailLabel: DateFormat('MMMM y', _locale).format(month),
            summary: ShiftSummary.from(grouped[i]),
          );
        }(),
    ];
  }

  /// Whole calendar days between two moments.
  ///
  /// Deliberately not `to.difference(from).inDays`: a spring-forward day is 23
  /// hours long, which truncates to 0 and drops that day's shifts into the
  /// previous bar.
  static int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static List<Shift> _unique(Iterable<Shift> shifts) {
    final unique = <String, Shift>{};
    for (final shift in shifts) {
      unique.putIfAbsent(shift.id, () => shift);
    }
    return unique.values.toList();
  }

  static const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _monthInitials = [
    'J',
    'F',
    'M',
    'A',
    'M',
    'J',
    'J',
    'A',
    'S',
    'O',
    'N',
    'D',
  ];

  static double _currency(num value) => (value * 100).round() / 100;
}
