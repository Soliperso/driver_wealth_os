import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'stat_tile.dart';

/// One figure on a [MetricPanel]: what it is called, what it reads, and whether
/// it is describing a loss.
typedef PanelMetric = ({String label, String value, bool loss});

/// A recessed block of supporting figures, sitting deliberately below the one
/// number its card is about.
///
/// The alternative — fencing each figure off from its neighbours with hairlines
/// — made the card read as a table competing with its own headline. One quiet
/// block reads as reference material underneath it.
///
/// Extracted from History's hero card so Coach can put the numbers behind an
/// insight under the sentence that states it, instead of leaving them buried
/// mid-prose.
class MetricPanel extends StatelessWidget {
  const MetricPanel({super.key, required this.rows});

  final List<List<PanelMetric>> rows;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: Space.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final metric in rows[index])
                  Expanded(
                    child: StatTile(
                      label: metric.label,
                      value: metric.value,
                      emphasis: StatEmphasis.compact,
                      valueColor: metric.loss ? colors.error : null,
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
