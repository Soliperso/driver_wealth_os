import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// What a feature is still waiting for before it can say anything true.
///
/// The honest alternative to hiding a card until it has data: the section stays
/// visible and shows how far along its own history is, so a feature never
/// appears to vanish from the app. Pairs the bar with a plain count, because a
/// bar alone tells a driver they are partway to something without saying to
/// what.
///
/// History spelled this out twice at two different bar heights and Coach used a
/// static `LEARNING` chip that reported no progress at all. One widget, so the
/// same waiting state looks the same wherever the driver meets it.
class LearningProgress extends StatelessWidget {
  const LearningProgress({
    super.key,
    required this.done,
    required this.needed,
    required this.caption,
    this.barKey,
  });

  /// How much of [needed] the driver's history already supports.
  final int done;
  final int needed;

  /// The count in words, e.g. `'2 of 4 patterns tracked'`.
  final String caption;

  /// Set when a test needs to find this particular bar among several.
  final Key? barKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LinearProgressIndicator(
        key: barKey,
        // A denominator of zero would be a caller's bug, but it must not be a
        // crash in front of a driver.
        value: needed <= 0 ? 1 : (done / needed).clamp(0.0, 1.0),
        minHeight: 6,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      const SizedBox(height: Space.sm),
      Text(
        caption,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
