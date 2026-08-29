import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class SoftBackground extends StatelessWidget {
  const SoftBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [AppColors.darkBackgroundTop, AppColors.darkBackground]
                : const [
                    AppColors.lightBackgroundTop,
                    AppColors.lightBackground,
                  ],
          ),
        ),
        child: Stack(
          children: const [
            Positioned(
              top: -150,
              right: -120,
              child: _SoftGlow(size: 380, color: Color(0xFF85CDBB)),
            ),
            Positioned(
              bottom: -200,
              left: -150,
              child: _SoftGlow(size: 440, color: Color(0xFFB2DDD2)),
            ),
          ],
        ),
      ),
    );
  }
}

class SoftScaffold extends StatelessWidget {
  const SoftScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.actions,
    this.toolbarHeight = 56,
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final double toolbarHeight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      extendBodyBehindAppBar: false,
      appBar: title == null && titleWidget == null
          ? null
          : AppBar(
              title: titleWidget ?? Text(title!),
              actions: actions,
              toolbarHeight: toolbarHeight,
              backgroundColor: colors.surface.withValues(alpha: .94),
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              shape: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .42),
                ),
              ),
            ),
      body: Stack(children: [const SoftBackground(), body]),
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius,
    this.tint,
    this.blur,
    this.elevation = Elevation.raised,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Overrides the rank's radius. Prefer setting [elevation] so surfaces stay
  /// on the shared scale.
  final double? radius;
  final Color? tint;
  final double? blur;

  /// Which rank this surface occupies. Drives radius, blur and border together
  /// so a hero reads heavier than a list row.
  final Elevation elevation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        tint ??
        (isDark
            ? colors.surfaceContainerLow.withValues(alpha: .84)
            : Colors.white.withValues(alpha: .86));
    final effectiveRadius = radius ?? elevation.radius;
    final effectiveBlur = blur ?? elevation.blur;
    final borderRadius = BorderRadius.circular(effectiveRadius);

    // No cast shadow. Rank comes from radius, blur and border; see [Elevation].
    // The border is what separates a near-white card from a near-white
    // background — without it the surface only reads where it happens to
    // overlap a glow.
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: borderRadius,
            border: Border.all(
              // Dark mode needs a fainter edge: the same alpha that reads as a
              // hairline on white reads as a drawn outline on near-black.
              color: colors.outlineVariant.withValues(
                alpha: elevation.borderOpacity * (isDark ? .5 : .8),
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SoftIcon extends StatelessWidget {
  const SoftIcon(this.icon, {super.key, this.size = 20, this.circleSize = 36});

  final IconData icon;
  final double size;

  /// Diameter of the tinted circle. 36 is the inline size used beside a title;
  /// empty states hand it a larger circle so the glyph can carry the card.
  final double circleSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: circleSize,
      height: circleSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size, color: colors.primary),
    );
  }
}

class _SoftGlow extends StatelessWidget {
  const _SoftGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // At 12% the glows were invisible in light mode and the background read as
    // flat grey. Dark stays low: the same strength there turns into a visible
    // green haze rather than a suggestion of depth.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: isDark ? .10 : .20),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
