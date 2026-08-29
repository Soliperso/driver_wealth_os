import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_money.dart';
import '../../../core/widgets/metric_panel.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../shifts/domain/period_analytics.dart';
import '../../shifts/domain/shift_summary.dart';

/// The screen's headline: what the selected period actually produced.
///
/// This card used to show two lifetime figures — total profit and a shift count
/// — which never changed and answered no question a driver was asking. It now
/// carries the period selector and a compact answer to what was earned, what
/// it cost, how far it took, and what was kept.
class PeriodHeroCard extends StatelessWidget {
  const PeriodHeroCard({
    super.key,
    required this.performance,
    required this.period,
    required this.now,
    required this.onPeriodChanged,
    required this.onStep,
  });

  final PeriodPerformance performance;
  final ReportPeriod period;
  final DateTime now;
  final ValueChanged<ReportPeriod> onPeriodChanged;

  /// −1 for the previous window, +1 for the next.
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final range = performance.range;
    final summary = performance.summary;
    final atPresent = range.isCurrent(now);
    // A period that cost more than it earned must not print its per-hour and
    // per-mile figures in the profit colour.
    final lost = summary.netProfit < 0;

    return GlassSurface(
      // The hero rank, like Coach's and Today's. This card is the one thing
      // History is about, and it was sitting on the rank reserved for rows and
      // chips — a tier below the analytics cards underneath it.
      elevation: Elevation.hero,
      padding: const EdgeInsets.all(Space.xl),
      // Lightened along with the added figures: the same saturation behind
      // twice the content made the card shout.
      tint: colors.primaryContainer.withValues(alpha: .55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodSelector(selected: period, onChanged: onPeriodChanged),
          Space.gapLg,
          Row(
            children: [
              IconButton(
                key: const ValueKey('period-previous'),
                tooltip: 'Previous ${period.label.toLowerCase()}',
                visualDensity: VisualDensity.compact,
                onPressed: () => onStep(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  range.label(now),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('period-next'),
                tooltip: 'Next ${period.label.toLowerCase()}',
                visualDensity: VisualDensity.compact,
                // There is nothing to show past the present.
                onPressed: atPresent ? null : () => onStep(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          // The stepper's icon buttons carry their own generous tap padding, so
          // a full gap under them opened a band of dead space above the figure
          // the card exists to show.
          Space.gapMd,
          if (performance.isEmpty)
            _EmptyPeriod(range: range)
          else ...[
            Row(
              children: [
                // Expanded, not Flexible: the label claims the whole line so
                // the keep rate is pushed out to the right edge, and it still
                // ellipsizes rather than shoving the pill off a narrow screen.
                Expanded(
                  child: Text(
                    // The shift count used to occupy a line of its own at the
                    // foot of the card. It is a caption, not a metric, so it
                    // rides with the label instead.
                    'TRUE PROFIT · ${summary.shiftCount} '
                    '${summary.shiftCount == 1 ? 'SESSION' : 'SESSIONS'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      letterSpacing: .6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                _KeepRatePill(summary: summary),
              ],
            ),
            Space.gapXs,
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedMoney(
                  value: summary.netProfit,
                  style: textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures,
                    color: lost ? colors.error : null,
                  ),
                ),
              ),
            ),
            if (performance.netProfitDelta != null) ...[
              Space.gapSm,
              _TrendLine(
                delta: performance.netProfitDelta!,
                change: performance.netProfitChange,
                period: period,
              ),
            ],
            Space.gapLg,
            // The six supporting figures sit together on their own recessed
            // panel rather than being fenced off from each other by hairlines.
            // Six vertical rules and six heavy numbers made the card read as a
            // table competing with its own headline; one quiet block reads as
            // reference material underneath it.
            MetricPanel(
              rows: [
                [
                  (
                    label: 'Gross',
                    value: Money.cents(summary.gross),
                    loss: false,
                  ),
                  (
                    label: 'Costs',
                    value: Money.cents(summary.totalExpenses),
                    loss: false,
                  ),
                  (
                    label: 'Miles',
                    value: Money.compactNumber(summary.miles),
                    loss: false,
                  ),
                ],
                [
                  (
                    label: 'Net / hr',
                    // A rate needs a denominator. Zero hours would print
                    // "$0.00", which reads as a terrible week rather than an
                    // unmeasurable one.
                    value: summary.hours == 0
                        ? '—'
                        : Money.cents(summary.netPerHour),
                    loss: lost,
                  ),
                  (
                    label: 'Net / mi',
                    value: summary.miles == 0
                        ? '—'
                        : Money.cents(summary.netPerMile),
                    loss: lost,
                  ),
                  (
                    label: 'Hours',
                    value: Money.hours(summary.hours),
                    loss: false,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Day / Week / Month / Year.
///
/// Hand-rolled rather than a [SegmentedButton] because four worded segments do
/// not fit inside a padded card on a narrow phone at that component's minimum
/// tap width, and abbreviating them to D/W/M/Y makes the control a puzzle.
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onChanged});

  final ReportPeriod selected;
  final ValueChanged<ReportPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        children: [
          for (final option in ReportPeriod.values)
            Expanded(
              child: Semantics(
                selected: option == selected,
                button: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: ValueKey('period-${option.name}'),
                    borderRadius: BorderRadius.circular(Radii.sm - 3),
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    onTap: option == selected ? null : () => onChanged(option),
                    // Update the translucent selection fill in one frame.
                    // Cross-fading adjacent fills looked like a flash on the
                    // pale glass surface used by the light theme.
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: option == selected
                            ? colors.surface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(Radii.sm - 3),
                      ),
                      child: Text(
                        option.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontWeight: option == selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: option == selected
                                  ? colors.onSurface
                                  : colors.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How this period compares with the one before it.
///
/// The analytics layer has computed this since the period report existed, and
/// nothing on screen ever showed it: the driver could see that this week made
/// $587 but not that it was $120 better than last week, which is the question
/// a weekly figure actually raises.
///
/// The dollar delta leads because it is always meaningful. The percentage is
/// only shown when the prior period turned a profit — "+150%" against a losing
/// week describes nothing.
class _TrendLine extends StatelessWidget {
  const _TrendLine({
    required this.delta,
    required this.change,
    required this.period,
  });

  final double delta;
  final double? change;
  final ReportPeriod period;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final flat = delta == 0;
    final up = delta > 0;
    // Direction is carried by the arrow and the signed figure as well as the
    // colour, so it survives for a driver who cannot separate red from green.
    final color = flat
        ? colors.onSurfaceVariant
        : up
        ? colors.primary
        : colors.error;

    return Row(
      key: const ValueKey('period-trend'),
      children: [
        Icon(
          flat
              ? Icons.trending_flat_rounded
              : up
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: Space.xs + 2),
        Flexible(
          child: Text(
            flat
                ? 'Level with ${_previousLabel(period)}'
                : '${Money.signed(delta)}'
                      '${change == null ? '' : ' (${Money.percent(change!.abs())})'} '
                      'vs ${_previousLabel(period)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ],
    );
  }

  static String _previousLabel(ReportPeriod period) => switch (period) {
    ReportPeriod.day => 'yesterday',
    ReportPeriod.week => 'last week',
    ReportPeriod.month => 'last month',
    ReportPeriod.year => 'last year',
  };
}

class _KeepRatePill extends StatelessWidget {
  const _KeepRatePill({required this.summary});

  final ShiftSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.gross <= 0) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final lost = summary.netProfit < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: lost
            ? colors.errorContainer.withValues(alpha: .62)
            : colors.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        lost ? 'Loss' : '${Money.percent(summary.keepRate)} kept',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: lost ? colors.onErrorContainer : colors.primary,
          fontWeight: FontWeight.w800,
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }
}

class _EmptyPeriod extends StatelessWidget {
  const _EmptyPeriod({required this.range});

  final PeriodRange range;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'No sessions',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Nothing recorded for ${range.plainLabel}.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
