import 'package:flutter/widgets.dart';

/// A strict 4pt scale.
///
/// The screens previously used ad-hoc values (26, 22, 18, 14, 13, 11, 9, 7, 5,
/// 3, 2), which is the main reason the layout read as slightly arbitrary. Every
/// gap should come from here so vertical rhythm is consistent across screens.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Clears the floating bottom navigation bar. Only the compact layout has
  /// one, so the wide/rail layout must not pay for it.
  static const bottomNavClearance = 92.0;

  static const gapXs = SizedBox(height: xs);
  static const gapSm = SizedBox(height: sm);
  static const gapMd = SizedBox(height: md);
  static const gapLg = SizedBox(height: lg);
  static const gapXl = SizedBox(height: xl);
  static const gapXxl = SizedBox(height: xxl);
}

/// Corner radii, paired with [Elevation] to give surfaces a deliberate rank.
abstract final class Radii {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 22.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

/// Three ranks of surface. Everything used to be one flat glass card at radius
/// 22, so a hero, a stat panel and a list row all carried the same weight and
/// nothing guided the eye.
enum Elevation {
  /// The one thing the screen is about.
  hero(radius: Radii.xl, blur: 16, borderOpacity: .55, shadowOpacity: .10),

  /// Supporting panels.
  raised(radius: Radii.lg, blur: 12, borderOpacity: .45, shadowOpacity: .05),

  /// Rows and chips that should recede.
  flat(radius: Radii.md, blur: 8, borderOpacity: .35, shadowOpacity: 0);

  const Elevation({
    required this.radius,
    required this.blur,
    required this.borderOpacity,
    required this.shadowOpacity,
  });

  final double radius;
  final double blur;
  final double borderOpacity;
  final double shadowOpacity;
}
