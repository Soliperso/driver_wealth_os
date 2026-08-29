import 'package:flutter/material.dart';

import '../charts/chart_palette.dart';
import '../theme/app_spacing.dart';
import 'brand_mark.dart';
import 'fade_slide_in.dart';
import 'soft_surfaces.dart';
import 'stat_tile.dart';

/// The logo, the product name and what the product is.
///
/// Onboarding and sign-in each grew an identical private copy of this, which
/// meant the app's own name was defined in two places.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        const BrandMark(size: 38),
        const SizedBox(width: Space.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Driver Wealth',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: -.25,
              ),
            ),
            Text(
              'Profit intelligence for drivers',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

/// The first-run page: a wordmark, a claim, and one card that asks for
/// something.
///
/// Every screen a driver can reach before they are inside the app — onboarding
/// and each step of the auth flow — is this shape. It lives here so those
/// screens cannot drift apart, which is exactly what had happened: two files
/// held the same layout with the same magic numbers copied between them.
class HeroFormScaffold extends StatelessWidget {
  const HeroFormScaffold({
    super.key,
    required this.eyebrow,
    required this.headline,
    required this.subcopy,
    required this.card,
    this.aside,
  });

  /// The small uppercase line above the headline.
  final String eyebrow;

  /// Two short lines. Written with an explicit line break rather than left to
  /// wrap, so the break lands where it was intended to.
  final String headline;

  final String subcopy;

  /// An optional block between the pitch and the card — the profit preview on
  /// first run, nothing on the screens a returning driver sees.
  final Widget? aside;

  /// What the page is asking for.
  final Widget card;

  /// The card's inner padding, which the hero text is also inset by so the
  /// headline lines up with the card's content rather than its edge.
  static const _gutter = Space.xl;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          const SoftBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.lg,
                  Space.lg,
                  Space.xl,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - Space.xxl - Space.lg,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FadeSlideIn(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: _gutter,
                              ),
                              child: Wordmark(),
                            ),
                          ),
                          Space.gapXxl,
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 60),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: _gutter,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    eyebrow,
                                    style: textTheme.labelMedium?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.25,
                                    ),
                                  ),
                                  Space.gapMd,
                                  Text(
                                    headline,
                                    style: textTheme.headlineMedium?.copyWith(
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  Space.gapLg,
                                  Text(
                                    subcopy,
                                    style: textTheme.bodyLarge?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (aside != null) ...[
                            Space.gapXl,
                            FadeSlideIn(
                              delay: const Duration(milliseconds: 120),
                              child: aside!,
                            ),
                          ],
                          Space.gapXl,
                          FadeSlideIn(
                            delay: Duration(
                              milliseconds: aside == null ? 120 : 180,
                            ),
                            child: GlassSurface(
                              padding: const EdgeInsets.all(_gutter),
                              elevation: Elevation.hero,
                              child: card,
                            ),
                          ),
                        ],
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

/// What the app does, in three numbers, before the driver has entered any.
///
/// The screen used to ask for a name having shown nothing, so "what you
/// earned, what it cost, what you kept" was a claim rather than a
/// demonstration. The figures are an illustration and are labelled as one.
class ProfitPreview extends StatelessWidget {
  const ProfitPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = ChartPalette.of(context);

    return Semantics(
      label:
          'An example session: 312 dollars earned, 84 dollars of costs, '
          '228 dollars kept.',
      container: true,
      child: ExcludeSemantics(
        child: GlassSurface(
          elevation: Elevation.flat,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Row(
            children: [
              const Expanded(
                child: StatTile(
                  label: 'Earned',
                  value: r'$312',
                  emphasis: StatEmphasis.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
              _Step(icon: Icons.remove_rounded, color: colors.onSurfaceVariant),
              const Expanded(
                child: StatTile(
                  label: 'Costs',
                  value: r'$84',
                  emphasis: StatEmphasis.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
              _Step(
                icon: Icons.drag_handle_rounded,
                color: colors.onSurfaceVariant,
              ),
              Expanded(
                child: StatTile(
                  label: 'You keep',
                  value: r'$228',
                  emphasis: StatEmphasis.compact,
                  valueColor: palette.positive,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    // Pushed down to sit on the figures rather than between the labels above
    // them.
    padding: const EdgeInsets.only(left: Space.sm, right: Space.sm, top: 14),
    child: Icon(icon, size: 14, color: color.withValues(alpha: .7)),
  );
}
