import 'package:flutter/material.dart';

import '../../../core/charts/earnings_dna_heatmap.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/grade_badge.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/section_card_title.dart';
import '../../../core/widgets/section_heading.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../settings/domain/measurement_units.dart';
import '../../shifts/domain/shift_analytics.dart';

class BestTimesScreen extends StatelessWidget {
  const BestTimesScreen({
    super.key,
    required this.patterns,
    required this.units,
  });

  final List<EarningsPattern> patterns;
  final MeasurementUnits units;

  @override
  Widget build(BuildContext context) {
    final ranked =
        patterns
            .where((pattern) => pattern.grade != PatternGrade.pending)
            .toList()
          ..sort((a, b) => b.netPerHour.compareTo(a.netPerHour));

    return SoftScaffold(
      title: 'Best times',
      body: PageFrame(
        maxWidth: 720,
        child: ListView(
          children: [
            // The grid, moved here from History's own Earnings DNA card. The
            // two were the same reading of the same
            // `ShiftAnalytics.earningsPatterns` data on two screens — down to
            // printing the same "N of 4 patterns tracked" sentence — and this
            // is the screen the app now leads to for it. The heatmap was the
            // one thing History's copy showed that this one did not.
            GlassSurface(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionCardTitle(
                    icon: Icons.fingerprint_rounded,
                    title: 'Earnings DNA',
                    subtitle:
                        'Which day and time of the week actually pays, graded '
                        'against your own reviewed sessions.',
                  ),
                  Space.gapLg,
                  EarningsDnaHeatmap(patterns: patterns),
                ],
              ),
            ),
            Space.gapXl,
            const SectionHeading(title: 'RANKED BY TRUE HOURLY'),
            Space.gapMd,
            Text(
              'Reviewed sessions only. These are observations from your '
              'history, not forecasts.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Space.gapLg,
            for (final (index, pattern) in ranked.indexed) ...[
              if (index > 0) Space.gapMd,
              _PatternCard(rank: index + 1, pattern: pattern, units: units),
            ],
            const SizedBox(height: Space.bottomNavClearance),
          ],
        ),
      ),
    );
  }
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({
    required this.rank,
    required this.pattern,
    required this.units,
  });

  final int rank;
  final EarningsPattern pattern;
  final MeasurementUnits units;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      elevation: rank == 1 ? Elevation.raised : Elevation.flat,
      tint: rank == 1 ? colors.primaryContainer.withValues(alpha: .62) : null,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank == 1
                      ? colors.primary.withValues(alpha: .14)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  '$rank',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: rank == 1 ? colors.primary : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pattern.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      pattern.timeBlock.range,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              GradeBadge(grade: pattern.grade),
            ],
          ),
          const SizedBox(height: Space.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: StatTile(
                  label: 'True hourly',
                  value: '${units.cents(pattern.netPerHour)}/hr',
                  emphasis: StatEmphasis.normal,
                  valueColor: pattern.netPerHour < 0 ? colors.error : null,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'True Profit',
                  value: units.cents(pattern.netProfit),
                  emphasis: StatEmphasis.normal,
                  valueColor: pattern.netProfit < 0 ? colors.error : null,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'History',
                  value:
                      '${pattern.shiftCount} ${pattern.shiftCount == 1 ? 'session' : 'sessions'}',
                  emphasis: StatEmphasis.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
