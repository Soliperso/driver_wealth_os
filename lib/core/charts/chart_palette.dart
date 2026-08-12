import 'package:flutter/material.dart';

/// Chart colours, validated rather than eyeballed.
///
/// The sequential ramp was checked with the data-visualisation validator in
/// both modes (monotone lightness, adjacent ΔL ≥ 0.06, light end clearing the
/// surface, single hue):
///
///   light  #7FC0AD #4FA894 #24806D #0B4C42   light end 2.09:1 on white
///   dark   #79D7BE #4FB8A0 #2E9280 #1A6A5C   dark  end 2.70:1 on #121C19
///
/// Dark is a selected set of steps against the dark surface, not an automatic
/// inversion of the light ramp.
class ChartPalette {
  const ChartPalette({
    required this.ramp,
    required this.positive,
    required this.negative,
    required this.context,
    required this.grid,
    required this.emptyCell,
  });

  /// Ordinal, light → dark. Index 0 is the weakest grade.
  final List<Color> ramp;

  /// Profit and loss are a *status* pair, not two categories: they mean good
  /// and bad. Both are paired with a label or grade letter so meaning never
  /// rests on colour alone.
  final Color positive;
  final Color negative;

  /// De-emphasis fill for the prior-week comparison. Deliberately recessive and
  /// therefore below the 3:1 mark threshold, so the comparison is always also
  /// stated in words next to the chart.
  final Color context;

  final Color grid;
  final Color emptyCell;

  static const _lightRamp = [
    Color(0xFF7FC0AD),
    Color(0xFF4FA894),
    Color(0xFF24806D),
    Color(0xFF0B4C42),
  ];

  static const _darkRamp = [
    Color(0xFF1A6A5C),
    Color(0xFF2E9280),
    Color(0xFF4FB8A0),
    Color(0xFF79D7BE),
  ];

  static ChartPalette of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const ChartPalette(
            // Magnitude reads brighter against a dark surface, so the ramp's
            // anchor flips: the strongest grade is the lightest step.
            ramp: _darkRamp,
            positive: Color(0xFF79D7BE),
            negative: Color(0xFFFFB4AB),
            context: Color(0xFF5C6F69),
            grid: Color(0xFF44534E),
            emptyCell: Color(0xFF192622),
          )
        : const ChartPalette(
            ramp: _lightRamp,
            positive: Color(0xFF146B5B),
            negative: Color(0xFFB3261E),
            context: Color(0xFF9AACA6),
            grid: Color(0xFFC3D0CB),
            emptyCell: Color(0xFFF1F5F3),
          );
  }

  /// Grade A is the strongest, so it takes the ramp's heaviest step.
  Color forGradeIndex(int index, int total) {
    if (total <= 1) return ramp.last;
    final position = ((total - 1 - index) / (total - 1)) * (ramp.length - 1);
    return ramp[position.round().clamp(0, ramp.length - 1)];
  }
}
