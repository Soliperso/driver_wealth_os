import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/period_analytics.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeriodRange', () {
    test('a week runs Monday through Sunday', () {
      final range = PeriodRange.containing(
        DateTime(2026, 8, 14),
        ReportPeriod.week,
      );

      expect(range.start, DateTime(2026, 8, 10));
      expect(range.end, DateTime(2026, 8, 17));
      expect(range.contains(DateTime(2026, 8, 16, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 8, 17)), isFalse);
    });

    test('a month ends on the first of the next month', () {
      final range = PeriodRange.containing(
        DateTime(2026, 8, 14),
        ReportPeriod.month,
      );

      expect(range.start, DateTime(2026, 8, 1));
      expect(range.end, DateTime(2026, 9, 1));
    });

    test('stepping back from January lands in the previous December', () {
      final january = PeriodRange.containing(
        DateTime(2026, 1, 15),
        ReportPeriod.month,
      );

      expect(january.previous().start, DateTime(2025, 12, 1));
      expect(january.previous().end, DateTime(2026, 1, 1));
    });

    test('stepping forward from December rolls the year over', () {
      final december = PeriodRange.containing(
        DateTime(2026, 12, 15),
        ReportPeriod.month,
      );

      expect(december.next().start, DateTime(2027, 1, 1));
    });

    test('the current window is labelled by name, not by date', () {
      final now = DateTime(2026, 8, 14);
      final thisWeek = PeriodRange.containing(now, ReportPeriod.week);
      final lastWeek = thisWeek.previous();

      expect(thisWeek.label(now), 'This week');
      expect(thisWeek.isCurrent(now), isTrue);
      expect(lastWeek.label(now), 'Aug 3–9');
      expect(lastWeek.isCurrent(now), isFalse);
    });

    test('a week spanning two months names both', () {
      final now = DateTime(2026, 8, 14);
      final range = PeriodRange.containing(
        DateTime(2026, 7, 30),
        ReportPeriod.week,
      );

      expect(range.label(now), 'Jul 27–Aug 2');
    });
  });

  group('PeriodAnalytics buckets', () {
    test('a week produces seven buckets, Monday first', () {
      final result = PeriodAnalytics.of(
        [_shift(id: 'a', date: DateTime(2026, 8, 12, 18), gross: 120)],
        ReportPeriod.week,
        DateTime(2026, 8, 14),
      );

      expect(result.buckets, hasLength(7));
      expect(result.buckets.map((b) => b.label), [
        'M',
        'T',
        'W',
        'T',
        'F',
        'S',
        'S',
      ]);
      // Wednesday the 12th is index 2.
      expect(result.buckets[2].netProfit, 120);
      expect(result.buckets[2].shiftCount, 1);
      expect(result.buckets[0].netProfit, 0);
    });

    test('a month produces one bucket per calendar day', () {
      final result = PeriodAnalytics.of(
        [_shift(id: 'a', date: DateTime(2026, 8, 31, 20), gross: 90)],
        ReportPeriod.month,
        DateTime(2026, 8, 14),
      );

      expect(result.buckets, hasLength(31));
      expect(result.buckets.last.netProfit, 90);
      // 31 ticks will not fit on a phone, so only every seventh is drawn.
      expect(result.labelStride, 7);
    });

    test('a leap February produces 29 buckets', () {
      final result = PeriodAnalytics.of(
        const [],
        ReportPeriod.month,
        DateTime(2028, 2, 10),
      );

      expect(result.buckets, hasLength(29));
    });

    test('a year produces twelve month buckets', () {
      final result = PeriodAnalytics.of(
        [
          _shift(id: 'jan', date: DateTime(2026, 1, 9, 12), gross: 100),
          _shift(id: 'dec', date: DateTime(2026, 12, 9, 12), gross: 300),
        ],
        ReportPeriod.year,
        DateTime(2026, 8, 14),
      );

      expect(result.buckets, hasLength(12));
      expect(result.buckets.first.netProfit, 100);
      expect(result.buckets.last.netProfit, 300);
      expect(result.buckets.last.detailLabel, 'December 2026');
    });

    test('a day produces one bucket per shift and no ghost bars', () {
      final result = PeriodAnalytics.of(
        [
          _shift(id: 'a', date: DateTime(2026, 8, 14, 9), gross: 50),
          _shift(id: 'b', date: DateTime(2026, 8, 14, 19), gross: 80),
          _shift(id: 'yesterday', date: DateTime(2026, 8, 13, 9), gross: 40),
        ],
        ReportPeriod.day,
        DateTime(2026, 8, 14),
      );

      expect(result.buckets, hasLength(2));
      expect(result.buckets.map((b) => b.netProfit), [50, 80]);
      // Lining yesterday's second shift up behind today's compares nothing.
      expect(result.previousBuckets, isEmpty);
      // The prior day still counts toward the comparison totals.
      expect(result.previousSummary.netProfit, 40);
    });

    test('a shorter prior month is truncated to align with the current one', () {
      // March has 31 buckets, February 28 — the ghost series must not run long
      // or short of the bars it sits behind.
      final result = PeriodAnalytics.of(
        [_shift(id: 'feb', date: DateTime(2026, 2, 20, 12), gross: 100)],
        ReportPeriod.month,
        DateTime(2026, 3, 15),
      );

      expect(result.buckets, hasLength(31));
      expect(result.previousBuckets, hasLength(28));
      expect(result.previousBuckets[19], 100);
    });

    test('a longer prior month is clipped to the current bucket count', () {
      final result = PeriodAnalytics.of(
        [_shift(id: 'jan', date: DateTime(2026, 1, 31, 12), gross: 100)],
        ReportPeriod.month,
        DateTime(2026, 2, 15),
      );

      expect(result.buckets, hasLength(28));
      expect(result.previousBuckets, hasLength(28));
    });
  });

  group('PeriodAnalytics totals', () {
    test('duplicate ids are counted once', () {
      final shift = _shift(
        id: 'a',
        date: DateTime(2026, 8, 12, 18),
        gross: 120,
      );

      final result = PeriodAnalytics.of(
        [shift, shift, shift],
        ReportPeriod.week,
        DateTime(2026, 8, 14),
      );

      expect(result.summary.shiftCount, 1);
      expect(result.summary.netProfit, 120);
      expect(result.buckets[2].shiftCount, 1);
    });

    test(
      'a losing prior period reports dollars, not a flattering percentage',
      () {
        final previous = _shift(
          id: 'previous',
          date: DateTime(2026, 7, 15, 9),
          gross: 0,
          directExpenses: 100,
        );
        final current = _shift(
          id: 'current',
          date: DateTime(2026, 8, 15, 9),
          gross: 50,
        );

        final result = PeriodAnalytics.of(
          [previous, current],
          ReportPeriod.month,
          DateTime(2026, 8, 14),
        );

        expect(result.previousSummary.netProfit, -100);
        expect(result.netProfitChange, isNull);
        expect(result.netProfitDelta, 150);
      },
    );

    test('no prior period means nothing to compare against', () {
      final result = PeriodAnalytics.of(
        [_shift(id: 'a', date: DateTime(2026, 8, 15, 9), gross: 80)],
        ReportPeriod.month,
        DateTime(2026, 8, 14),
      );

      expect(result.netProfitChange, isNull);
      // A first month is not an $80 improvement on anything.
      expect(result.netProfitDelta, isNull);
      expect(result.previousBuckets, isEmpty);
    });

    test(
      'an empty period reports itself as empty rather than as zero profit',
      () {
        final result = PeriodAnalytics.of(
          const [],
          ReportPeriod.month,
          DateTime(2026, 8, 14),
        );

        expect(result.isEmpty, isTrue);
        expect(result.summary.shiftCount, 0);
        expect(result.bestShift, isNull);
      },
    );

    test('the best shift ignores shifts with no hours recorded', () {
      final noHours = Shift.single(
        id: 'no-hours',
        platform: WorkPlatform.uber,
        gross: 500,
        hours: 0,
        miles: 0,
        directExpenses: 0,
        vehicleCostPerMile: 0,
        completedAt: DateTime(2026, 8, 11, 9),
      );
      final tracked = _shift(
        id: 'tracked',
        date: DateTime(2026, 8, 12, 9),
        gross: 100,
      );

      final result = PeriodAnalytics.of(
        [noHours, tracked],
        ReportPeriod.week,
        DateTime(2026, 8, 14),
      );

      expect(result.bestShift?.id, 'tracked');
    });
  });

  test('total expenses equal gross minus true profit', () {
    final result = PeriodAnalytics.of(
      [
        _shift(
          id: 'a',
          date: DateTime(2026, 8, 12, 9),
          gross: 200,
          directExpenses: 30,
          miles: 100,
          vehicleRate: .20,
        ),
      ],
      ReportPeriod.week,
      DateTime(2026, 8, 14),
    );

    // $30 direct plus 100 miles at $0.20 = $50 of cost against $200 earned.
    expect(result.summary.totalExpenses, 50);
    expect(result.summary.netProfit, 150);
    expect(result.summary.gross - result.summary.totalExpenses, 150);
  });
}

Shift _shift({
  required String id,
  required DateTime date,
  required double gross,
  double hours = 4,
  double directExpenses = 0,
  double miles = 0,
  double vehicleRate = 0,
}) => Shift.single(
  id: id,
  platform: WorkPlatform.uber,
  gross: gross,
  hours: hours,
  miles: miles,
  directExpenses: directExpenses,
  vehicleCostPerMile: vehicleRate,
  completedAt: date,
);
