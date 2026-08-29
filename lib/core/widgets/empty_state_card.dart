import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'soft_surfaces.dart';

/// The one shape every "nothing here yet" screen uses.
///
/// History and Coach had drifted: a bare 60px glyph against a 20px [SoftIcon],
/// two title weights, two card heights. Both render this now, so the first
/// screen a new driver sees reads the same wherever they land.
///
/// The card claims the height it is given and centres its content, which is
/// what leaves the air above and below the copy.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;

  /// The one thing to do about it, if there is one.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final act = action;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: GlassSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.xl,
              vertical: Space.xxxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The glyph is the illustration here, not a label's
                    // bullet, so it gets a circle twice the inline size.
                    SoftIcon(icon, size: 34, circleSize: 72),
                    const SizedBox(height: Space.xl),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      // Nothing on this screen competes with it, so it does
                      // not need to shout to win — and at full onSurface a
                      // near-black line over grey body copy was the only
                      // thing the eye landed on.
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: .78,
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (act != null) ...[
                      const SizedBox(height: Space.xl),
                      // The card's own action carries the app's button
                      // metrics, so a screen only has to hand over a plain
                      // [OutlinedButton] and both empty states match.
                      OutlinedButtonTheme(
                        data: OutlinedButtonThemeData(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            minimumSize: const Size(0, 52),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            side: BorderSide(
                              color: theme.colorScheme.primary.withValues(
                                alpha: .38,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.1,
                            ),
                          ),
                        ),
                        child: act,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
