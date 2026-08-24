import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// The label above a screen-level group of content.
///
/// Distinct from the headings *inside* a card, which are `titleMedium` w800
/// over a `bodySmall` subtitle. This one is deliberately quieter — it names a
/// region of the page rather than titling a card, so it recedes into
/// [ColorScheme.onSurfaceVariant] and earns its separation from letterSpacing
/// instead of weight.
///
/// Callers pass the title already uppercased, e.g. `'RECENT SHIFTS'`.
///
/// Lives here rather than on Today because History needs the same idiom; it
/// previously had a third heading style of its own, which is what made the two
/// screens read as though they came from different apps.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.trailing,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final String title;

  /// A figure that belongs to the group as a whole — a count, a total. Shown
  /// when there is no action; an action takes precedence, since a tappable
  /// affordance is worth more than a restated number.
  final Widget? trailing;

  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = actionLabel;
    final action = onAction;
    // An action outranks [trailing]: a tappable affordance is worth more to the
    // reader than a restated number.
    final tail = label != null && action != null
        ? TextButton(
            key: actionKey,
            onPressed: action,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                const SizedBox(width: Space.xs),
                const Icon(Icons.arrow_forward_rounded, size: 15),
              ],
            ),
          )
        : trailing;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        ?tail,
      ],
    );
  }
}
