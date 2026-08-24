import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'soft_surfaces.dart';

/// The heading inside an analytics card.
///
/// Cards on History and Coach are structurally identical — same surface, same
/// rank, same title over the same subtitle — so scrolling past them read as one
/// wall of white boxes with nothing to tell them apart until each title was
/// read. The icon gives each card an identity at a glance, reusing the
/// [SoftIcon] treatment Settings already uses for exactly that.
///
/// The icon leads both lines rather than only the title, so the subtitle stays
/// aligned under the words it belongs to instead of starting back at the card
/// edge.
///
/// Lives in `core` rather than on History because Coach needs the same idiom;
/// it previously had an eyebrow-over-title of its own, which is part of what
/// made the two screens read as though they came from different apps.
class SectionCardTitle extends StatelessWidget {
  const SectionCardTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// A control belonging to the card as a whole, such as the chart's
  /// bars-or-line toggle.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = subtitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoftIcon(icon, size: 18),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (text != null) ...[
                const SizedBox(height: Space.xs),
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: Space.md), trailing!],
      ],
    );
  }
}
