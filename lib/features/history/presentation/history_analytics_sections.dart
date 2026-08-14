import 'package:flutter/material.dart';

import '../../../core/charts/chart_palette.dart';
import '../../../core/charts/earnings_dna_heatmap.dart';
import '../../../core/charts/weekly_profit_chart.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_analytics.dart';

class WeeklyPerformanceSection extends StatelessWidget {
  const WeeklyPerformanceSection({super.key, required this.shifts});

  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final performance = ShiftAnalytics.weekly(shifts);
    final summary = performance.summary;
    return GlassSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'This week',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (performance.netProfitChange != null)
                _ChangeBadge(change: performance.netProfitChange!)
              else if (performance.netProfitDelta != null)
                _ChangeBadge(delta: performance.netProfitDelta!),
            ],
          ),
          const SizedBox(height: 4),
          Text('Monday–Sunday', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          if (summary.shiftCount == 0)
            Text(
              'No completed shifts this week yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _WeeklyMetric(
                    label: 'True profit',
                    value: Money.cents(summary.netProfit),
                  ),
                ),
                Expanded(
                  child: _WeeklyMetric(
                    label: 'Net / hour',
                    value: Money.cents(summary.netPerHour),
                  ),
                ),
                Expanded(
                  child: _WeeklyMetric(
                    label: 'Keep rate',
                    value: Money.percent(summary.keepRate),
                  ),
                ),
              ],
            ),
            Space.gapXl,
            WeeklyProfitChart(
              currentWeek: performance.dailyNetProfit,
              previousWeek: performance.previousDailyNetProfit,
            ),
            // The prior-week bars are deliberately recessive, so the
            // comparison is also stated in words rather than resting on a
            // low-contrast fill alone.
            if (performance.previousSummary.shiftCount > 0) ...[
              Space.gapMd,
              Text(
                'Last week: ${Money.cents(performance.previousSummary.netProfit)} '
                'across ${performance.previousSummary.shiftCount} '
                '${performance.previousSummary.shiftCount == 1 ? 'shift' : 'shifts'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (performance.bestShift != null && summary.shiftCount > 1) ...[
              const Divider(height: 28),
              Text(
                'Best shift: ${performance.bestShift!.platform.displayName} at '
                '${Money.cents(performance.bestShift!.netPerHour)}/hr',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class EarningsDnaSection extends StatelessWidget {
  const EarningsDnaSection({super.key, required this.shifts});

  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final patterns = ShiftAnalytics.earningsPatterns(shifts);
    final ready = patterns.length >= 4;
    return GlassSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Earnings DNA',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            ready
                ? 'Relative grades compare your own day-and-time patterns.'
                : 'Track 4 distinct day-and-time patterns to unlock relative grades.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (patterns.isEmpty)
            const Text('No pattern data yet.')
          else if (!ready) ...[
            LinearProgressIndicator(
              value: (patterns.length / 4).clamp(0.0, 1.0),
              minHeight: 7,
              borderRadius: BorderRadius.circular(99),
            ),
            const SizedBox(height: 9),
            Text(
              '${patterns.length} of 4 patterns tracked',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            // The grid is the point: which day and time of week actually pays.
            EarningsDnaHeatmap(patterns: patterns),
            const Divider(height: 28),
            Text(
              'Strongest patterns',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Space.gapMd,
            for (final pattern in patterns.take(3)) ...[
              _PatternRow(pattern: pattern),
              if (pattern != patterns.take(3).last) const Divider(height: 20),
            ],
          ],
        ],
      ),
    );
  }
}

class _WeeklyMetric extends StatelessWidget {
  const _WeeklyMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

/// Week-over-week movement.
///
/// Shows a percentage only when the prior week made a profit. Against a losing
/// week there is no ratio that means anything, so the dollar difference is
/// shown instead of a flattering fiction.
class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({this.change, this.delta})
    : assert(
        change != null || delta != null,
        'A badge with nothing to report should not be built',
      );

  final double? change;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final value = change ?? delta!;
    final positive = value >= 0;
    final color = positive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    final label = change != null
        ? '${positive ? '+' : ''}${(change! * 100).toStringAsFixed(0)}%'
        : Money.signed(delta!);
    return Container(
      key: const ValueKey('weekly-change-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }
}

class _PatternRow extends StatelessWidget {
  const _PatternRow({required this.pattern});

  final EarningsPattern pattern;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _GradeBadge(grade: pattern.grade),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pattern.label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              '${pattern.timeBlock.range} · ${pattern.shiftCount} ${pattern.shiftCount == 1 ? 'shift' : 'shifts'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      Text(
        '${Money.cents(pattern.netPerHour)}/hr',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontFeatures: tabularFigures,
        ),
      ),
    ],
  );
}

class _GradeBadge extends StatelessWidget {
  const _GradeBadge({required this.grade});

  final PatternGrade grade;

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    // A–D is an ordered scale, so it takes one hue with monotone lightness.
    // The previous badge used four unrelated hues (teal, blue, brown, red),
    // which spent the identity channel on something rank already conveys — and
    // borrowed the error colour, whose reserved meaning here is a loss.
    final color = grade == PatternGrade.pending
        ? Theme.of(context).colorScheme.outline
        : palette.forGradeIndex(grade.index - PatternGrade.a.index, 4);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(Radii.sm - 2),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        grade.name.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
