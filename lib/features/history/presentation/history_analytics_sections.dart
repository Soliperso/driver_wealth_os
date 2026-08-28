import 'package:flutter/material.dart';

import '../../../core/charts/period_profit_chart.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/learning_progress.dart';
import '../../../core/widgets/section_card_title.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/domain/work_platform.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../shifts/domain/period_analytics.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_summary.dart';

/// The chart card for whichever window the hero card is showing.
///
/// It carries no stat tiles of its own: true profit, net per hour and keep rate
/// all live in the hero above, and printing them twice on one screen made the
/// two cards compete to be the summary.
class PeriodPerformanceSection extends StatefulWidget {
  const PeriodPerformanceSection({super.key, required this.performance});

  final PeriodPerformance performance;

  @override
  State<PeriodPerformanceSection> createState() =>
      _PeriodPerformanceSectionState();
}

class _PeriodPerformanceSectionState extends State<PeriodPerformanceSection> {
  ProfitChartStyle _chartStyle = ProfitChartStyle.bars;

  @override
  Widget build(BuildContext context) {
    final performance = widget.performance;
    final summary = performance.summary;
    final previous = performance.previousSummary;
    final period = performance.range.period;

    return GlassSurface(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The shared card heading, whose `trailing` slot exists for exactly
          // this toggle. It was hand-rolled here with its own gaps and no
          // icon, so the one card on History that carries a chart was also the
          // one card that did not look like the others.
          SectionCardTitle(
            // Not a bar-chart glyph: the toggle to its right is already drawn
            // with one, and repeating it in the heading made the leading icon
            // look like a third state of that control.
            icon: Icons.query_stats_rounded,
            title: switch (period) {
              ReportPeriod.day => 'Profit by session',
              ReportPeriod.week || ReportPeriod.month => 'Profit by day',
              ReportPeriod.year => 'Profit by month',
            },
            subtitle: performance.range.plainLabel,
            trailing: _ChartStyleToggle(
              value: _chartStyle,
              onChanged: (value) => setState(() => _chartStyle = value),
            ),
          ),
          Space.gapLg,
          if (summary.shiftCount == 0)
            Text(
              'No completed sessions in this period yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            PeriodProfitChart(
              buckets: performance.buckets,
              previousBuckets: performance.previousBuckets,
              labelStride: performance.labelStride,
              comparisonLabel: _comparisonLabel(period),
              style: _chartStyle,
              // The prior-period bars are deliberately recessive, so the
              // comparison is also stated in words rather than resting on a
              // low-contrast fill alone.
              idleSummary: previous.shiftCount > 0
                  ? '${_comparisonLabel(period)}: ${Money.cents(previous.netProfit)} '
                        'across ${previous.shiftCount} '
                        '${previous.shiftCount == 1 ? 'session' : 'sessions'}.\n'
                        '${_interactionHint(_chartStyle)}.'
                  : '${_interactionHint(_chartStyle)}.',
            ),
            if (performance.bestShift != null && summary.shiftCount > 1) ...[
              const Divider(height: 28),
              Text(
                'Best session: ${performance.bestShift!.platform.displayName} at '
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

  static String _comparisonLabel(ReportPeriod period) => switch (period) {
    ReportPeriod.day => 'Yesterday',
    ReportPeriod.week => 'Last week',
    ReportPeriod.month => 'Last month',
    ReportPeriod.year => 'Last year',
  };

  static String _interactionHint(ProfitChartStyle style) => switch (style) {
    ProfitChartStyle.bars => 'Tap a bar for its full numbers',
    ProfitChartStyle.line => 'Tap a point for its full numbers',
  };
}

class _ChartStyleToggle extends StatelessWidget {
  const _ChartStyleToggle({required this.value, required this.onChanged});

  final ProfitChartStyle value;
  final ValueChanged<ProfitChartStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChartStyleOption(
            key: const ValueKey('chart-style-bars'),
            label: 'Bars',
            icon: Icons.bar_chart_rounded,
            selected: value == ProfitChartStyle.bars,
            onTap: () => onChanged(ProfitChartStyle.bars),
          ),
          _ChartStyleOption(
            key: const ValueKey('chart-style-line'),
            label: 'Line',
            icon: Icons.show_chart_rounded,
            selected: value == ProfitChartStyle.line,
            onTap: () => onChanged(ProfitChartStyle.line),
          ),
        ],
      ),
    );
  }
}

class _ChartStyleOption extends StatelessWidget {
  const _ChartStyleOption({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: '$label chart',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: selected ? null : onTap,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          borderRadius: BorderRadius.circular(Radii.sm - 2),
          child: Container(
            // Square-ish and icon-only, as in Finmate: the header's job is the
            // title, and two words of chrome next to it competed with it.
            constraints: const BoxConstraints(minWidth: 38, minHeight: 32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: .16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.sm - 2),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compares platforms once there is enough reviewed evidence. Until then it
/// stays visible as a small, honest learning state so the feature does not
/// appear to vanish from History.
class PlatformPerformanceSection extends StatelessWidget {
  const PlatformPerformanceSection({super.key, required this.shifts});

  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final grouped = <WorkPlatform, List<Shift>>{};
    final seen = <String>{};
    for (final shift in shifts) {
      if (!seen.add(shift.id) || !shift.costsReviewed || shift.hours <= 0) {
        continue;
      }
      grouped.putIfAbsent(shift.platform, () => []).add(shift);
    }

    final comparable =
        grouped.entries
            .where((entry) => entry.value.length >= 2)
            .map(
              (entry) => (
                platform: entry.key,
                shifts: entry.value,
                summary: ShiftSummary.from(entry.value),
              ),
            )
            .toList()
          ..sort(
            (a, b) => b.summary.netPerHour.compareTo(a.summary.netPerHour),
          );

    final ready = comparable.length >= 2;
    // Progress has to be measured against the gate the section actually
    // applies — two platforms with two reviewed shifts *each*. Counting every
    // platform's shifts filled the bar to "2 of 2 platforms · 4 of 4 sessions"
    // while the section still said it was waiting for data.
    final counts = [for (final shifts in grouped.values) shifts.length]
      ..sort((a, b) => b.compareTo(a));
    final contenders = counts.take(2);
    final trackedPlatforms = contenders.where((count) => count >= 2).length;
    final trackedShifts = contenders.fold<int>(
      0,
      (total, count) => total + count.clamp(0, 2),
    );

    return Column(
      children: [
        const SizedBox(height: Space.md),
        GlassSurface(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCardTitle(
                icon: Icons.compare_arrows_rounded,
                title: 'Platform comparison',
                subtitle: ready
                    ? 'Based on reviewed costs and at least 2 sessions each.'
                    : 'Track 2 reviewed sessions on 2 platforms to compare pay.',
              ),
              Space.gapLg,
              if (!ready)
                // The shared waiting state, as on Coach. This bar was one of
                // the two hand-rolled copies at differing heights that
                // [LearningProgress] was extracted to replace.
                LearningProgress(
                  barKey: const ValueKey('platform-comparison-learning'),
                  done: trackedShifts,
                  needed: 4,
                  caption:
                      '$trackedPlatforms of 2 platforms · '
                      '$trackedShifts of 4 sessions',
                )
              else
                for (
                  var index = 0;
                  index < comparable.take(3).length;
                  index++
                ) ...[
                  _PlatformPerformanceRow(data: comparable[index]),
                  if (index < comparable.take(3).length - 1)
                    const Divider(height: Space.xl),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PlatformPerformanceRow extends StatelessWidget {
  const _PlatformPerformanceRow({required this.data});

  final ({WorkPlatform platform, List<Shift> shifts, ShiftSummary summary})
  data;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      PlatformLogo(platform: data.platform, size: 30),
      const SizedBox(width: Space.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.platform.displayName,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${data.shifts.length} sessions',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      Text(
        '${Money.cents(data.summary.netPerHour)}/hr',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontFeatures: tabularFigures,
        ),
      ),
    ],
  );
}

