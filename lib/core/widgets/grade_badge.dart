import 'package:flutter/material.dart';

import '../../features/shifts/domain/shift_analytics.dart';
import '../charts/chart_palette.dart';
import '../theme/app_spacing.dart';

/// Where one day-and-time pattern ranks against the driver's own others.
///
/// History and Best times each grew a badge of their own — different shapes,
/// different colour logic, and a disagreement about what a pending grade looks
/// like — so the same A-tier pattern was drawn two ways depending on which
/// screen you reached it from. This is the reconciliation: History's ordered
/// colour scale, with Best times' honest em dash for a grade that does not
/// exist yet.
class GradeBadge extends StatelessWidget {
  const GradeBadge({super.key, required this.grade});

  final PatternGrade grade;

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    final pending = grade == PatternGrade.pending;
    // A–D is an ordered scale, so it takes one hue with monotone lightness.
    // An earlier badge used four unrelated hues (teal, blue, brown, red), which
    // spent the identity channel on something rank already conveys — and
    // borrowed the error colour, whose reserved meaning here is a loss.
    final color = pending
        ? Theme.of(context).colorScheme.outline
        : palette.forGradeIndex(grade.index - PatternGrade.a.index, 4);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(Radii.sm - 2),
      ),
      child: Text(
        // Not `grade.name`: "PENDING" does not fit in a 34pt square, and a
        // grade nobody has earned yet is better said with a dash than a word.
        pending ? '—' : grade.name.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
