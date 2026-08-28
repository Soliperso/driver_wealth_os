import 'dart:math' as math;

import 'package:driver_wealth_os/core/charts/period_profit_chart.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/period_analytics.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const idle = 'Tap a bar for its full numbers.';

  /// Taps the centre of bucket [index] of [count] across the plot.
  Future<void> tapBar(WidgetTester tester, int index, int count) async {
    final plot = tester.getRect(
      find.byKey(const ValueKey('period-profit-plot')),
    );
    final slot = plot.width / count;
    await tester.tapAt(
      Offset(plot.left + slot * index + slot / 2, plot.center.dy),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a bar reports that bucket, tapping again clears it', (
    tester,
  ) async {
    final performance = PeriodAnalytics.of(
      [
        _shift(id: 'wed', date: DateTime(2026, 8, 12, 18), gross: 200),
        _shift(id: 'fri', date: DateTime(2026, 8, 14, 18), gross: 90),
      ],
      ReportPeriod.week,
      DateTime(2026, 8, 14),
    );

    await tester.pumpWidget(_host(performance, idle));

    expect(find.text(idle), findsOneWidget);

    // Wednesday is index 2 of seven.
    await tapBar(tester, 2, 7);

    expect(find.text(idle), findsNothing);
    expect(find.text('Wednesday, Aug 12 · 1 session'), findsOneWidget);
    expect(find.text('\$200.00'), findsOneWidget);

    // Dragging across to Friday swaps the panel without clearing it.
    await tapBar(tester, 4, 7);
    expect(find.text('Friday, Aug 14 · 1 session'), findsOneWidget);

    // Tapping the selected bar again clears the selection.
    await tapBar(tester, 4, 7);
    expect(find.text(idle), findsOneWidget);
  });

  testWidgets('a day with no shifts says so rather than showing zeros', (
    tester,
  ) async {
    final performance = PeriodAnalytics.of(
      [_shift(id: 'wed', date: DateTime(2026, 8, 12, 18), gross: 200)],
      ReportPeriod.week,
      DateTime(2026, 8, 14),
    );

    await tester.pumpWidget(_host(performance, idle));
    // Monday, index 0, has nothing recorded.
    await tapBar(tester, 0, 7);

    expect(find.text('Monday, Aug 10'), findsOneWidget);
    expect(find.text('No sessions'), findsOneWidget);
  });

  testWidgets('a selection does not survive a change of period', (
    tester,
  ) async {
    final shifts = [
      _shift(id: 'wed', date: DateTime(2026, 8, 12, 18), gross: 200),
    ];

    await tester.pumpWidget(
      _host(
        PeriodAnalytics.of(shifts, ReportPeriod.week, DateTime(2026, 8, 14)),
        idle,
      ),
    );
    await tapBar(tester, 2, 7);
    expect(find.text('Wednesday, Aug 12 · 1 session'), findsOneWidget);

    // Swap to a month: index 2 means something entirely different now.
    await tester.pumpWidget(
      _host(
        PeriodAnalytics.of(shifts, ReportPeriod.month, DateTime(2026, 8, 14)),
        idle,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(idle), findsOneWidget);
    expect(find.text('Wednesday, Aug 12 · 1 session'), findsNothing);
  });

  testWidgets('a loss bucket is not printed in the profit colour', (
    tester,
  ) async {
    final performance = PeriodAnalytics.of(
      [
        _shift(
          id: 'bad',
          date: DateTime(2026, 8, 12, 18),
          gross: 20,
          directExpenses: 80,
        ),
      ],
      ReportPeriod.week,
      DateTime(2026, 8, 14),
    );

    await tester.pumpWidget(_host(performance, idle));
    await tapBar(tester, 2, 7);

    final amount = tester.widget<Text>(find.text('-\$60.00'));
    final context = tester.element(find.byType(PeriodProfitChart));
    expect(amount.style?.color, Theme.of(context).colorScheme.error);
  });

  test('every bucket with money in it is labelled, losses included', () {
    final labels = _labelsFor([200, 0, 90, 0, -60, 0, 0]);

    expect(_texts(labels), containsAll(<String>['\$200', '\$90', '-\$60']));
    // Four of those days had no shift on them; a row of "$0" would be four
    // numbers that say nothing.
    expect(_texts(labels), isNot(contains('\$0')));
    // The loss hangs under its bar, every gain over the top of its own.
    final loss = labels.firstWhere((label) => label.index == 4);
    expect(loss.rect.top, greaterThan(_baselineY));
  });

  test('a selected bucket drops its label to the panel alone', () {
    expect(
      _texts(_labelsFor([200, 90])),
      containsAll(<String>['\$200', '\$90']),
    );

    // The neighbours stay: they are what the selected bucket is compared to.
    final labels = _texts(_labelsFor([200, 90], selectedIndex: 1));
    expect(labels, isNot(contains('\$90')));
    expect(labels, contains('\$200'));
  });

  test('a month drops colliding labels rather than overlapping them', () {
    // Thirty-one slots across a phone is ~10pt each, far less than a figure
    // needs, so most of the month cannot be labelled. The peak still has to be.
    final labels = _labelsFor([
      for (var day = 1; day <= 31; day++) day == 9 ? 400 : 100 + day.toDouble(),
    ]);

    expect(_texts(labels), contains('\$400'));
    expect(labels.length, lessThan(31));

    for (var i = 0; i < labels.length; i++) {
      for (var j = i + 1; j < labels.length; j++) {
        expect(
          labels[i].rect.overlaps(labels[j].rect),
          isFalse,
          reason: '${labels[i].text} overlaps ${labels[j].text}',
        );
      }
    }
  });

  test('a label is never printed across a neighbouring bar', () {
    // A quiet day beside a tall one: the small figure would otherwise be
    // centred over its neighbour's column.
    final labels = _labelsFor([400, 12]);
    final bars = _barsFor([400, 12]);

    for (final label in labels) {
      for (final bar in bars.entries) {
        if (bar.key == label.index) continue;
        expect(label.rect.overlaps(bar.value), isFalse);
      }
    }
  });

  testWidgets('line view keeps the same tap-to-inspect interaction', (
    tester,
  ) async {
    const lineIdle = 'Tap a point for its full numbers.';
    final performance = PeriodAnalytics.of(
      [
        _shift(id: 'wed', date: DateTime(2026, 8, 12, 18), gross: 200),
        _shift(id: 'fri', date: DateTime(2026, 8, 14, 18), gross: 90),
      ],
      ReportPeriod.week,
      DateTime(2026, 8, 14),
    );

    await tester.pumpWidget(
      _host(performance, lineIdle, style: ProfitChartStyle.line),
    );
    expect(find.text(lineIdle), findsOneWidget);

    await tapBar(tester, 2, 7);
    expect(find.text('Wednesday, Aug 12 · 1 session'), findsOneWidget);
    expect(find.text('\$200.00'), findsOneWidget);
  });
}

/// The plot the label placement is exercised against: a phone-width card, and
/// the geometry the chart itself uses.
const _plot = Size(300, 176);
const _plotTop = 14.0;
const _baselineY = 140.0;

/// Rebuilds what the painter hands the placement pass: one rod per bucket,
/// centred in its slot and capped at the chart's 12pt rod width.
Map<int, Rect> _barsFor(List<double> values) {
  final peak = values.fold<double>(1, (best, value) => math.max(best, value));
  final trough = values.fold<double>(
    -1,
    (worst, value) => math.min(worst, value),
  );
  // One linear scale either side of zero, as in _PlotGeometry, with a band left
  // clear at both ends for the labels.
  final unit = math.min(
    (_baselineY - _plotTop) / peak,
    (_plot.height - _baselineY - _plotTop) / -trough,
  );

  final slot = _plot.width / values.length;
  final width = math.min(12.0, slot - 4);
  return {
    for (var i = 0; i < values.length; i++)
      if (values[i] != 0)
        i: () {
          final centre = i * slot + slot / 2;
          final height = math.max(values[i].abs() * unit, 6.0);
          return Rect.fromLTWH(
            centre - width / 2,
            values[i] < 0 ? _baselineY : _baselineY - height,
            width,
            height,
          );
        }(),
  };
}

List<ProfitLabel> _labelsFor(List<double> values, {int? selectedIndex}) {
  final bars = _barsFor(values);
  return layOutProfitLabels(
    anchors: [
      for (final bar in bars.entries)
        (
          index: bar.key,
          value: values[bar.key],
          centre: bar.value.center.dx,
          anchorY: values[bar.key] < 0 ? bar.value.bottom : bar.value.top,
          below: values[bar.key] < 0,
        ),
    ],
    size: _plot,
    baselineY: _baselineY,
    peakStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
    valueStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    obstacles: bars,
    selectedIndex: selectedIndex,
  );
}

List<String> _texts(List<ProfitLabel> labels) => [
  for (final label in labels) label.text,
];

Widget _host(
  PeriodPerformance performance,
  String idle, {
  ProfitChartStyle style = ProfitChartStyle.bars,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 350,
        child: PeriodProfitChart(
          buckets: performance.buckets,
          previousBuckets: performance.previousBuckets,
          labelStride: performance.labelStride,
          comparisonLabel: 'Last week',
          idleSummary: idle,
          style: style,
        ),
      ),
    ),
  ),
);

Shift _shift({
  required String id,
  required DateTime date,
  required double gross,
  double hours = 4,
  double directExpenses = 0,
}) => Shift.single(
  id: id,
  platform: WorkPlatform.uber,
  gross: gross,
  hours: hours,
  miles: 0,
  directExpenses: directExpenses,
  vehicleCostPerMile: 0,
  completedAt: date,
);
