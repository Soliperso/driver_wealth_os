import 'package:flutter/material.dart';

import '../../features/shifts/domain/shift_analytics.dart';
import '../format/money.dart';
import '../theme/app_spacing.dart';
import 'chart_palette.dart';

/// Earnings DNA as the grid it actually is.
///
/// `ShiftAnalytics.earningsPatterns` already groups by weekday × time block, so
/// the data was always two-dimensional; it was previously flattened into a
/// list, which hid exactly the day-and-time structure the feature exists to
/// reveal.
///
/// Grade is ordinal (A is better than D), so it takes a single-hue ramp with
/// monotone lightness rather than categorical hues. The grade letter is drawn
/// in each cell, so the reading never depends on colour alone.
class EarningsDnaHeatmap extends StatelessWidget {
  const EarningsDnaHeatmap({super.key, required this.patterns});

  final List<EarningsPattern> patterns;

  static const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final blocks = TimeBlock.values;

    final byCell = <String, EarningsPattern>{
      for (final pattern in patterns)
        '${pattern.weekday}-${pattern.timeBlock.name}': pattern,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) ...[
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  block.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              for (var weekday = 1; weekday <= 7; weekday++)
                Expanded(
                  child: _Cell(
                    pattern: byCell['$weekday-${block.name}'],
                    palette: palette,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
        ],
        Row(
          children: [
            const SizedBox(width: 92),
            for (final day in _weekdayLabels)
              Expanded(
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        Space.gapMd,
        _RampLegend(palette: palette),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.pattern, required this.palette});

  final EarningsPattern? pattern;
  final ChartPalette palette;

  @override
  Widget build(BuildContext context) {
    final entry = pattern;
    final graded = entry != null && entry.grade != PatternGrade.pending;
    final gradeIndex = graded ? entry.grade.index - PatternGrade.a.index : 0;
    final fill = graded
        ? palette.forGradeIndex(gradeIndex, 4)
        : palette.emptyCell;

    return Semantics(
      label: entry == null
          ? null
          : '${entry.label}, ${graded ? 'grade ${entry.grade.name.toUpperCase()}, ' : ''}'
                '${Money.cents(entry.netPerHour)} net per hour',
      child: Padding(
        // A 2px gap of surface between cells so adjacent fills never blend.
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: AspectRatio(
          aspectRatio: 1.35,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: Text(
                // Secondary encoding: the grade is legible without colour.
                graded ? entry.grade.name.toUpperCase() : '',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  // Picked from the fill's own luminance rather than the
                  // grade's rank: the ramp's anchor flips between modes, so in
                  // dark mode grade A is the *lightest* cell and white text on
                  // it would be unreadable.
                  color: fill.computeLuminance() > .5
                      ? const Color(0xFF0B1210)
                      : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RampLegend extends StatelessWidget {
  const _RampLegend({required this.palette});

  final ChartPalette palette;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        Flexible(
          child: Text('Weaker', style: style, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: Space.sm),
        // The swatches shrink before the labels do, so the ramp stays readable
        // on a narrow phone instead of pushing the row off-screen.
        for (var index = 3; index >= 0; index--) ...[
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 18, minWidth: 8),
              height: 8,
              decoration: BoxDecoration(
                color: palette.forGradeIndex(index, 4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
        const SizedBox(width: Space.xs + 2),
        Flexible(
          child: Text(
            'Stronger',
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
