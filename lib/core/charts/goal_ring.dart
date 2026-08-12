import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format/money.dart';
import 'chart_palette.dart';

/// A single ratio against a limit, drawn as a meter on a same-ramp track.
///
/// Deliberately not a two-slice pie: the reader's job is "how far along am I",
/// which an arc answers directly. The value is always written in the middle,
/// so the reading never depends on judging an angle.
class GoalRing extends StatelessWidget {
  const GoalRing({
    super.key,
    required this.progress,
    required this.centerValue,
    this.caption,
    this.diameter = 168,
    this.isLoss = false,
  });

  /// 0..1. Values above 1 are clamped; the caption carries any overshoot.
  final double progress;
  final String centerValue;
  final String? caption;
  final double diameter;
  final bool isLoss;

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    final colors = Theme.of(context).colorScheme;
    final clamped = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final accent = isLoss ? palette.negative : palette.positive;

    return Semantics(
      label:
          'Goal progress ${Money.percent(clamped)}, $centerValue'
          '${caption == null ? '' : ', $caption'}',
      excludeSemantics: true,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          painter: _GoalRingPainter(
            progress: clamped,
            accent: accent,
            track: accent.withValues(alpha: .14),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  centerValue,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalRingPainter extends CustomPainter {
  _GoalRingPainter({
    required this.progress,
    required this.accent,
    required this.track,
  });

  final double progress;
  final Color accent;
  final Color track;

  static const _stroke = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (math.min(size.width, size.height) - _stroke) / 2;
    final arcRect = Rect.fromCircle(center: centre, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, trackPaint);

    if (progress <= 0) return;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = accent;
    // Starts at twelve o'clock and runs clockwise, the direction people read
    // progress in.
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) =>
      old.progress != progress || old.accent != accent;
}
