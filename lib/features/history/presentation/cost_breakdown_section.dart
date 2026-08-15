import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../shifts/domain/shift_summary.dart';

/// What happened to every dollar earned in the period.
///
/// The hero card says the driver grossed $840 and kept $587. It does not say
/// where the other $252 went — and for an app whose entire premise is that
/// gross pay is a lie, that is the missing half of the story. Fuel and tolls
/// are money the driver watched leave their hand; the per-mile vehicle
/// allowance is the cost they never see, which is exactly why it needs its own
/// bar segment rather than being folded into a single "costs" total.
class CostBreakdownSection extends StatelessWidget {
  const CostBreakdownSection({super.key, required this.summary});

  final ShiftSummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    if (summary.gross <= 0) return const SizedBox.shrink();

    final lost = summary.netProfit < 0;
    // Costs are one family in two shades rather than two unrelated hues: they
    // mean the same kind of thing, and rank inside that family is all the
    // colour has to carry.
    final directColor = colors.tertiary;
    final vehicleColor = colors.tertiary.withValues(alpha: .45);
    final keptColor = colors.primary;

    // On a losing period the bar can only show the shape of the costs; there
    // is no kept slice to draw.
    final base = lost ? summary.totalExpenses : summary.gross;

    return GlassSurface(
      key: const ValueKey('cost-breakdown'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Where the money went',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            lost
                ? 'Costs came to more than this period earned.'
                : 'Every ${Money.whole(1)} earned, split into what you kept '
                      'and what it cost to earn it.',
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          Space.gapLg,
          _ProportionBar(
            segments: [
              if (!lost)
                (value: summary.netProfit, color: keptColor, label: 'Kept'),
              (
                value: summary.directExpenses,
                color: directColor,
                label: 'Fuel, tolls & parking',
              ),
              (
                value: summary.vehicleCost,
                color: vehicleColor,
                label: 'Vehicle wear',
              ),
            ],
            total: base,
          ),
          Space.gapLg,
          if (!lost)
            _BreakdownRow(
              color: keptColor,
              label: 'Take-home',
              amount: summary.netProfit,
              share: summary.netProfit / base,
            ),
          _BreakdownRow(
            color: directColor,
            label: 'Fuel, tolls & parking',
            amount: summary.directExpenses,
            share: base == 0 ? 0 : summary.directExpenses / base,
          ),
          _BreakdownRow(
            color: vehicleColor,
            label: 'Vehicle wear',
            amount: summary.vehicleCost,
            share: base == 0 ? 0 : summary.vehicleCost / base,
            // The one cost a driver never gets an invoice for, so it gets the
            // one line of explanation.
            note: summary.miles > 0
                ? 'Per-mile running cost across '
                      '${Money.compactNumber(summary.miles)} miles'
                : null,
          ),
          if (summary.miles > 0) ...[
            const Divider(height: 28),
            Row(
              children: [
                Icon(
                  Icons.route_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    lost
                        ? 'You lost ${Money.cents(summary.netPerMile.abs())} '
                              'for every mile driven.'
                        : 'You keep ${Money.cents(summary.netPerMile)} of every '
                              'mile you drive.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A single stacked bar: the whole period's earnings, cut into its parts.
class _ProportionBar extends StatelessWidget {
  const _ProportionBar({required this.segments, required this.total});

  final List<({double value, Color color, String label})> segments;
  final double total;

  static const _height = 14.0;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final segment in segments)
        if (segment.value > 0) segment,
    ];
    if (total <= 0 || visible.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: [
        for (final segment in visible)
          '${segment.label} ${Money.percent(segment.value / total)}',
      ].join(', '),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.pill),
        child: SizedBox(
          height: _height,
          child: Row(
            // Stretch, not the default centre: an empty ColoredBox given loose
            // height constraints collapses to nothing and the bar disappears.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final segment in visible)
                Expanded(
                  // Rounded to a thousandth so a sliver of a segment still
                  // claims a flex share rather than collapsing to nothing.
                  flex: (segment.value / total * 1000).round().clamp(1, 1000),
                  child: Padding(
                    // Hairline separators, so adjacent shades of the same hue
                    // stay countable.
                    padding: const EdgeInsets.only(right: 1),
                    child: ColoredBox(color: segment.color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.share,
    this.note,
  });

  final Color color;
  final String label;
  final double amount;
  final double share;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final detail = note;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: Space.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.cents(amount),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabularFigures,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Money.percent(share),
                style: textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
