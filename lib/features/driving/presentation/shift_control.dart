import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

/// What the control is offering to do next.
enum ShiftControlState {
  /// No session. The button starts one.
  idle,

  /// Counting. The button takes a break.
  driving,

  /// On a break. The button starts counting again.
  paused,
}

/// The one round control that runs a shift.
///
/// The same object in the same place across all three states, so the driver
/// learns one target instead of three buttons that happen to occupy the same
/// corner. Ending a shift stays a separate, deliberately less inviting
/// control — it is the only one of these actions that cannot be undone.
///
/// Stateless on purpose. The parent owns the clock that drives [ringProgress],
/// which keeps every repeating timer in this feature behind the one nullable
/// interval that tests already disable. A ticker in here would schedule a
/// frame forever and hang `pumpAndSettle` in every test that reaches this
/// screen — see the note on `_LiveDot` in driving_hero.dart.
class ShiftControl extends StatelessWidget {
  const ShiftControl({
    super.key,
    required this.state,
    required this.onPressed,
    this.ringProgress = 0,
    this.diameter = 120,
  });

  final ShiftControlState state;
  final VoidCallback onPressed;

  /// 0..1 around the ring. Zero leaves a plain bezel.
  ///
  /// Purely indicative: no figure the driver is paid on is read from it, so a
  /// frozen ticker costs nothing but a stale sweep.
  final double ringProgress;

  /// Outer diameter, bezel included. The default is deliberately large and the
  /// same in all three states: this is the only control on the screen a driver
  /// reaches for while the car is stopped at a light, and it must not shrink
  /// or move between starting, pausing and resuming.
  final double diameter;

  /// Clear air between the ring and the button, so the ring reads as a bezel
  /// rather than a stray stroke against the fill.
  static const _ringGap = 5.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final (fill, foreground, icon, label, semantic) = switch (state) {
      ShiftControlState.idle => (
        colors.primary,
        colors.onPrimary,
        Icons.play_arrow_rounded,
        // Names the thing being started. "Start" alone leaves a driver to infer
        // it from the card, and this button also sits next to "Enter a shift
        // manually", which starts nothing.
        'Start Driving',
        'Start driving',
      ),
      ShiftControlState.driving => (
        colors.primary,
        colors.onPrimary,
        Icons.pause_rounded,
        'Pause',
        'Pause session',
      ),
      // A break has to be unmistakable against idle, because the two offer the
      // same icon and mistaking one for the other means a driver walks away
      // believing they are counted when they are not.
      ShiftControlState.paused => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        Icons.play_arrow_rounded,
        'Resume',
        'Resume session',
      ),
    };

    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: diameter,
            height: diameter,
            child: CustomPaint(
              painter: _ShiftRingPainter(
                progress: ringProgress,
                accent: state == ShiftControlState.paused
                    ? colors.tertiary
                    : colors.primary,
                track: colors.primary.withValues(alpha: .14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(
                  _ShiftRingPainter.stroke + _ringGap,
                ),
                child: Material(
                  color: fill,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: switch (state) {
                      ShiftControlState.idle => const ValueKey(
                        'start-driving-button',
                      ),
                      ShiftControlState.driving => const ValueKey(
                        'pause-shift-button',
                      ),
                      ShiftControlState.paused => const ValueKey(
                        'resume-shift-button',
                      ),
                    },
                    onTap: onPressed,
                    customBorder: const CircleBorder(),
                    child: Center(
                      child: Icon(
                        icon,
                        size: diameter * .42,
                        color: foreground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          // Spelled out rather than left to the icon alone: a bare triangle
          // does not say whether it starts a shift or resumes one, and that is
          // the distinction that matters most here.
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bezel. Modelled on `_GoalRingPainter` so the two rings in the app agree
/// on where zero is and which way round they run.
class _ShiftRingPainter extends CustomPainter {
  _ShiftRingPainter({
    required this.progress,
    required this.accent,
    required this.track,
  });

  final double progress;
  final Color accent;
  final Color track;

  static const stroke = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final arcRect = Rect.fromCircle(
      center: (Offset.zero & size).center,
      radius: radius,
    );

    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    if (progress <= 0) return;
    // Twelve o'clock, clockwise, matching GoalRing.
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_ShiftRingPainter old) =>
      old.progress != progress || old.accent != accent || old.track != track;
}
