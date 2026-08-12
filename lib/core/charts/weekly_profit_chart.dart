import 'package:flutter/material.dart';

import '../format/money.dart';
import '../theme/app_spacing.dart';
import 'chart_palette.dart';

/// Daily true profit for the current week, with the prior week behind it.
///
/// Form: the job is comparing magnitude across seven days, so bars. The prior
/// week is *context*, not a second identity, so it takes the de-emphasis grey
/// rather than a second categorical hue. Loss days take the status colour
/// because a negative day genuinely means "bad", not "series 2".
class WeeklyProfitChart extends StatelessWidget {
  const WeeklyProfitChart({
    super.key,
    required this.currentWeek,
    required this.previousWeek,
  });

  /// Seven values, Monday first. Zero means no shift that day.
  final List<double> currentWeek;
  final List<double> previousWeek;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    final peakIndex = _peakIndex(currentWeek);
    final scale = _scale();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two marks are present, so a legend is required: identity must never
        // rest on colour alone.
        Row(
          children: [
            // The card heading already says "This week", so the legend names
            // the marks without repeating it.
            _LegendSwatch(color: palette.positive, label: 'Current'),
            const SizedBox(width: Space.md),
            _LegendSwatch(color: palette.context, label: 'Last week'),
          ],
        ),
        Space.gapMd,
        Semantics(
          label: _semanticSummary(),
          excludeSemantics: true,
          child: SizedBox(
            height: 132,
            child: LayoutBuilder(
              builder: (context, constraints) => CustomPaint(
                size: Size(constraints.maxWidth, 132),
                painter: _WeeklyProfitPainter(
                  currentWeek: currentWeek,
                  previousWeek: previousWeek,
                  scale: scale,
                  palette: palette,
                  peakIndex: peakIndex,
                  labelStyle:
                      textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ) ??
                      const TextStyle(fontSize: 11),
                  peakLabelStyle:
                      textTheme.labelSmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabularFigures,
                      ) ??
                      const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        ),
        Space.gapSm,
        Row(
          children: [
            for (final day in _weekdays)
              Expanded(
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  double _scale() {
    final values = [...currentWeek, ...previousWeek].map((v) => v.abs());
    final peak = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    return peak == 0 ? 1 : peak;
  }

  /// Only the best day is labelled. A number on every bar is noise.
  static int _peakIndex(List<double> values) {
    var index = -1;
    var best = 0.0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] > best) {
        best = values[i];
        index = i;
      }
    }
    return index;
  }

  String _semanticSummary() {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final parts = <String>[];
    for (var i = 0; i < currentWeek.length && i < names.length; i++) {
      if (currentWeek[i] != 0) {
        parts.add('${names[i]} ${Money.cents(currentWeek[i])}');
      }
    }
    return parts.isEmpty
        ? 'No profit recorded this week'
        : 'True profit by day. ${parts.join(', ')}.';
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: Space.xs + 2),
      Text(
        label,
        // Labels wear text tokens, never the series colour.
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _WeeklyProfitPainter extends CustomPainter {
  _WeeklyProfitPainter({
    required this.currentWeek,
    required this.previousWeek,
    required this.scale,
    required this.palette,
    required this.peakIndex,
    required this.labelStyle,
    required this.peakLabelStyle,
  });

  final List<double> currentWeek;
  final List<double> previousWeek;
  final double scale;
  final ChartPalette palette;
  final int peakIndex;
  final TextStyle labelStyle;
  final TextStyle peakLabelStyle;

  static const _gap = 2.0;
  static const _radius = 4.0;
  static const _labelBand = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (currentWeek.isEmpty) return;
    final slot = size.width / currentWeek.length;
    final plotTop = _labelBand;
    final plotHeight = size.height - _labelBand;

    // Any loss pushes the baseline up so negative bars have room to hang.
    final hasLoss = [...currentWeek, ...previousWeek].any((v) => v < 0);
    final baselineY = plotTop + (hasLoss ? plotHeight * .68 : plotHeight);
    final upHeight = baselineY - plotTop;
    final downHeight = plotTop + plotHeight - baselineY;

    final grid = Paint()
      ..color = palette.grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baselineY), Offset(size.width, baselineY), grid);

    for (var i = 0; i < currentWeek.length; i++) {
      final left = i * slot;
      final barWidth = (slot - _gap * 2).clamp(4.0, 28.0);
      final centre = left + slot / 2;

      // Prior week sits behind and wider, reading as a track rather than a
      // competing bar.
      if (i < previousWeek.length && previousWeek[i] != 0) {
        _drawBar(
          canvas,
          centre: centre,
          width: barWidth * 1.5,
          value: previousWeek[i],
          baselineY: baselineY,
          upHeight: upHeight,
          downHeight: downHeight,
          color: palette.context.withValues(alpha: .38),
        );
      }

      final value = currentWeek[i];
      if (value == 0) continue;
      _drawBar(
        canvas,
        centre: centre,
        width: barWidth,
        value: value,
        baselineY: baselineY,
        upHeight: upHeight,
        downHeight: downHeight,
        color: value < 0 ? palette.negative : palette.positive,
      );

      if (i == peakIndex) {
        final height = (value.abs() / scale) * upHeight;
        _drawLabel(
          canvas,
          Money.whole(value),
          Offset(centre, baselineY - height - 2),
          peakLabelStyle,
          size.width,
        );
      }
    }
  }

  void _drawBar(
    Canvas canvas, {
    required double centre,
    required double width,
    required double value,
    required double baselineY,
    required double upHeight,
    required double downHeight,
    required Color color,
  }) {
    final available = value < 0 ? downHeight : upHeight;
    // A small value next to a large peak would otherwise round to a sliver a
    // couple of pixels tall — which matters most for a loss day, the exact bar
    // the driver needs to notice.
    const minVisible = 6.0;
    final height = ((value.abs() / scale) * available).clamp(
      minVisible,
      available,
    );
    if (height <= 0) return;
    final rect = value < 0
        ? Rect.fromLTWH(centre - width / 2, baselineY, width, height)
        : Rect.fromLTWH(centre - width / 2, baselineY - height, width, height);

    // Rounded only at the data end; the baseline end stays square so the bar
    // is visibly anchored to zero.
    final radius = Radius.circular(_radius);
    final rrect = value < 0
        ? RRect.fromRectAndCorners(
            rect,
            bottomLeft: radius,
            bottomRight: radius,
          )
        : RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius);
    canvas.drawRRect(rrect, Paint()..color = color);
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset anchor,
    TextStyle style,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = (anchor.dx - painter.width / 2).clamp(
      0.0,
      maxWidth - painter.width,
    );
    painter.paint(
      canvas,
      Offset(dx, (anchor.dy - painter.height).clamp(0.0, anchor.dy)),
    );
  }

  @override
  bool shouldRepaint(_WeeklyProfitPainter old) =>
      old.currentWeek != currentWeek ||
      old.previousWeek != previousWeek ||
      old.scale != scale ||
      old.peakIndex != peakIndex;
}
