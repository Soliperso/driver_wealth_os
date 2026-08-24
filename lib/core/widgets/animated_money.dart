import 'package:flutter/material.dart';

import '../../features/settings/domain/measurement_units.dart';

/// Counts a money figure up to its new value instead of snapping.
///
/// The movement is the point: it shows the number changed and roughly by how
/// much. Tabular figures keep the digits from reflowing while it runs.
///
/// Honours the platform's reduce-motion setting — when animations are
/// disabled the value simply appears, which is the correct behaviour for
/// anyone who gets motion sick or has asked the OS to calm things down.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney({
    super.key,
    required this.value,
    this.units = const MeasurementUnits(),
    this.style,
    this.whole = false,
    this.duration = const Duration(milliseconds: 650),
  });

  final double value;

  /// The driver's currency. Defaults to USD so the callers that have not been
  /// handed a preference yet render exactly as they did before.
  final MeasurementUnits units;

  final TextStyle? style;

  /// Drop the cents — for goals and targets, where they are noise.
  final bool whole;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final format = whole ? units.whole : units.cents;

    if (reduceMotion) {
      return Text(format(value), style: style);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => Text(format(animated), style: style),
    );
  }
}
