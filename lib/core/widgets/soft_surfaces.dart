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

  /// Which rank this surface occupies. Drives radius, blur, border and shadow
  /// together so a hero reads heavier than a list row.
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

    final surface = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: borderRadius,
            border: Border.all(
              color: colors.outlineVariant.withValues(
                alpha: isDark
                    ? elevation.borderOpacity * .75
                    : elevation.borderOpacity,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );

    if (elevation.shadowOpacity == 0) return surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : AppColors.brandDeep).withValues(
              alpha: isDark
                  ? elevation.shadowOpacity * 2
                  : elevation.shadowOpacity,
            ),
            blurRadius: elevation == Elevation.hero ? 28 : 16,
            offset: Offset(0, elevation == Elevation.hero ? 12 : 6),
          ),
        ],
      ),
      child: surface,
    );
  }
}

class SoftIcon extends StatelessWidget {
  const SoftIcon(this.icon, {super.key, this.size = 20});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .12),
        shape: BoxShape.circle,
        border: Border.all(color: colors.primary.withValues(alpha: .20)),
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
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: .12), color.withValues(alpha: 0)],
        ),
      ),
    ),
  );
}
