import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../features/shifts/domain/period_analytics.dart';
import '../format/money.dart';
import '../theme/app_spacing.dart';
import 'chart_palette.dart';

enum ProfitChartStyle { bars, line }

/// True profit per bucket for the selected period, with the prior period behind
/// it.
///
/// Form: the job is comparing magnitude across a sequence, so bars. The prior
/// period is *context*, not a second identity, so it takes the de-emphasis grey
/// rather than a second categorical hue. Loss buckets take the status colour
/// because a negative bucket genuinely means "bad", not "series 2".
///
/// Layout follows the same anatomy as the Finmate cash-flow chart: legend, a
/// gridded plot with a reserved value axis down the left, category labels along
/// the bottom, and a cross-fade between the two marks. Without the axis and
/// grid every bar was a shape with no magnitude attached — the plot said
/// "Monday was the tall one" but never "Monday was $250".
///
/// Every bucket carries its own figure. Where the slots are too narrow to fit
/// them all, the biggest numbers are placed first and the ones that would
/// collide are dropped, so what survives is always the part of the period worth
/// reading. Tapping or dragging across the plot selects a bucket and the panel
/// underneath reports its full figures.
class PeriodProfitChart extends StatefulWidget {
  const PeriodProfitChart({
    super.key,
    required this.buckets,
    required this.previousBuckets,
    required this.labelStride,
    required this.comparisonLabel,
    required this.idleSummary,
    this.style = ProfitChartStyle.bars,
  });

  final List<ProfitBucket> buckets;

  /// Index-aligned prior-period totals. Empty when a comparison would be
  /// meaningless.
  final List<double> previousBuckets;

  /// Draw every nth axis label; a month's 31 ticks will not fit on a phone.
  final int labelStride;

  /// Names the ghost series, e.g. "Last week".
  final String comparisonLabel;

  /// Shown in the detail panel while nothing is selected.
  final String idleSummary;

  /// Bars compare individual buckets; a line makes the overall direction
  /// easier to scan. Both views use the same values and selection model.
  final ProfitChartStyle style;

  @override
  State<PeriodProfitChart> createState() => _PeriodProfitChartState();
}

class _PeriodProfitChartState extends State<PeriodProfitChart> {
  int? _selected;

  /// The plot alone. With the label row underneath, the chart block comes to
  /// roughly the 200pt Finmate gives it.
  static const _plotHeight = 176.0;

  /// Reserved for the value axis, so the grid lines start where the numbers
  /// end rather than running underneath them.
  static const _axisWidth = 46.0;

  static const _labelRowHeight = 16.0;

  @override
  void didUpdateWidget(PeriodProfitChart old) {
    super.didUpdateWidget(old);
    // The period changed underneath us; an index into the old buckets means
    // nothing against the new ones.
    if (!identical(old.buckets, widget.buckets) ||
        (_selected != null && _selected! >= widget.buckets.length)) {
      _selected = null;
    }
  }

  int _indexFor(double dx, double width) {
    final slot = width / widget.buckets.length;
    return (dx / slot).floor().clamp(0, widget.buckets.length - 1);
  }

  void _select(int? index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    HapticFeedback.selectionClick();
    if (index != null) {
      final bucket = widget.buckets[index];
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${bucket.detailLabel}, ${Money.cents(bucket.netProfit)}',
        Directionality.of(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChartPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (widget.buckets.isEmpty) return const SizedBox.shrink();

    final values = [for (final bucket in widget.buckets) bucket.netProfit];
    final selected = _selected;
    final geometry = _PlotGeometry.from(
      values: values,
      previous: widget.previousBuckets,
      height: _plotHeight,
    );

    final axisLabelStyle =
        textTheme.labelSmall?.copyWith(
          fontSize: 10,
          color: colors.onSurfaceVariant,
          fontFeatures: tabularFigures,
        ) ??
        const TextStyle(fontSize: 10);

    // Every bucket carries its own figure, so the label that used to be the
    // only one on the chart keeps its weight and the rest sit a step back —
    // otherwise a week of bold numbers competes with the hero card above.
    final peakLabelStyle =
        textTheme.labelSmall?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w800,
          fontFeatures: tabularFigures,
        ) ??
        const TextStyle(fontSize: 11);
    final valueLabelStyle = peakLabelStyle.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two marks are present, so a legend is required: identity must never
        // rest on colour alone.
        Row(
          children: [
            _LegendSwatch(
              color: palette.positive,
              label: 'Current',
              line: widget.style == ProfitChartStyle.line,
            ),
            if (widget.previousBuckets.isNotEmpty) ...[
              const SizedBox(width: Space.md),
              _LegendSwatch(
                color: palette.context,
                label: widget.comparisonLabel,
                line: widget.style == ProfitChartStyle.line,
              ),
            ],
          ],
        ),
        Space.gapMd,
        Semantics(
          label: _semanticSummary(),
          excludeSemantics: true,
          child: SizedBox(
            height: _plotHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The axis sits outside the gesture area on purpose: a tap
                // meant for Monday's bar must not be swallowed by the numbers.
                SizedBox(
                  width: _axisWidth,
                  height: _plotHeight,
                  child: CustomPaint(
                    painter: _ValueAxisPainter(
                      geometry: geometry,
                      labelStyle: axisLabelStyle,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      return GestureDetector(
                        key: const ValueKey('period-profit-plot'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          final index = _indexFor(
                            details.localPosition.dx,
                            width,
                          );
                          // Tapping the selected bar again clears it.
                          _select(index == _selected ? null : index);
                        },
                        onHorizontalDragStart: (details) =>
                            _select(_indexFor(details.localPosition.dx, width)),
                        onHorizontalDragUpdate: (details) =>
                            _select(_indexFor(details.localPosition.dx, width)),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: CustomPaint(
                            key: ValueKey(widget.style),
                            size: Size(width, _plotHeight),
                            painter: _PeriodProfitPainter(
                              values: values,
                              previous: widget.previousBuckets,
                              geometry: geometry,
                              palette: palette,
                              selectedIndex: selected,
                              style: widget.style,
                              peakLabelStyle: peakLabelStyle,
                              valueLabelStyle: valueLabelStyle,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Space.gapSm,
        Padding(
          padding: const EdgeInsets.only(left: _axisWidth),
          child: SizedBox(
            // Fixed so the spilling labels below have a bounded box to sit in.
            height: _labelRowHeight,
            child: Row(
              children: [
                for (var i = 0; i < widget.buckets.length; i++)
                  Expanded(
                    // A month's 31 slots are ~10pt wide on a phone, which clipped
                    // "15" down to "1". Only every nth label is drawn, so a label
                    // is free to spill into the blank slots either side of it.
                    child: OverflowBox(
                      // minWidth must be released too: a Day period has few, wide
                      // slots, and inheriting a 76pt tight minimum under a 40pt
                      // maximum is not a legal constraint.
                      minWidth: 0,
                      maxWidth: 40,
                      alignment: Alignment.center,
                      child: Text(
                        i % widget.labelStride == 0
                            ? widget.buckets[i].label
                            : '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: textTheme.labelSmall?.copyWith(
                          color: i == selected
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          fontWeight: i == selected ? FontWeight.w800 : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Space.gapMd,
        _BucketDetailPanel(
          bucket: selected == null ? null : widget.buckets[selected],
          idleSummary: widget.idleSummary,
        ),
      ],
    );
  }

  String _semanticSummary() {
    final parts = <String>[
      for (final bucket in widget.buckets)
        if (bucket.netProfit != 0)
          '${bucket.detailLabel} ${Money.cents(bucket.netProfit)}',
    ];
    return parts.isEmpty
        ? 'No profit recorded in this period'
        : 'True profit by bucket. ${parts.join(', ')}.';
  }
}

/// Where zero sits, how tall a dollar is, and which values get a grid line.
///
/// One linear scale spans the whole plot rather than one scale above the
/// baseline and another below it: with a split scale a −$60 day and a +$60 day
/// drew to different heights, which is the one thing a value axis must never
/// do.
class _PlotGeometry {
  const _PlotGeometry({
    required this.top,
    required this.height,
    required this.axisMin,
    required this.axisMax,
    required this.step,
  });

  /// Clearance above the plot for the value labels.
  static const _labelBand = 14.0;

  final double top;
  final double height;
  final double axisMin;
  final double axisMax;
  final double step;

  factory _PlotGeometry.from({
    required List<double> values,
    required List<double> previous,
    required double height,
  }) {
    final all = [...values, ...previous];
    var peak = 0.0;
    var trough = 0.0;
    for (final value in all) {
      peak = math.max(peak, value);
      trough = math.min(trough, value);
    }

    // Headroom above the tallest bar, so a peak never touches the top rule.
    const padding = 1.15;
    final span = (peak - trough) * padding;
    final step = _niceStep(span);
    final axisMax = peak <= 0 ? 0.0 : (peak * padding / step).ceil() * step;
    final axisMin = trough >= 0
        ? 0.0
        : -((-trough * padding / step).ceil() * step);

    return _PlotGeometry(
      top: _labelBand,
      // A loss carries its figure under the bar, so it needs the same clearance
      // at the bottom that a gain gets at the top. Without it the label had
      // nowhere to go and flipped back above the baseline, which read as if it
      // belonged to the day beside it.
      height: height - _labelBand - (axisMin < 0 ? _labelBand : 0),
      // A period with nothing in it still needs a non-zero range or every
      // value maps to the same pixel.
      axisMin: axisMin,
      axisMax: axisMax == 0 && axisMin == 0 ? 1 : axisMax,
      step: step,
    );
  }

  double get _range => axisMax - axisMin;

  /// Pixels per dollar.
  double get unit => _range <= 0 ? 0 : height / _range;

  double yFor(double value) => top + (axisMax - value) * unit;

  double get baselineY => yFor(0);

  /// The values that earn a grid line, always including zero.
  List<double> get gridValues {
    if (step <= 0 || _range <= 0) return const [0];
    final lines = <double>[];
    for (var value = axisMin; value <= axisMax + step / 2; value += step) {
      // Floating-point drift across the loop makes a "0" that is not quite 0.
      lines.add(value.abs() < step / 1000 ? 0 : value);
    }
    return lines;
  }

  /// A 1/2/5×10ⁿ step, targeting about four grid lines. Finmate hard-codes its
  /// thresholds at 100/500/1000/5000, which is right for a net-worth chart but
  /// leaves a $180 driving day with a single grid line.
  static double _niceStep(double span) {
    if (span <= 0) return 1;
    final rough = span / 4;
    final magnitude = math
        .pow(10, (math.log(rough) / math.ln10).floor())
        .toDouble();
    final normalised = rough / magnitude;
    final factor = normalised <= 1
        ? 1.0
        : normalised <= 2
        ? 2.0
        : normalised <= 5
        ? 5.0
        : 10.0;
    return factor * magnitude;
  }
}

/// The value axis down the left edge.
class _ValueAxisPainter extends CustomPainter {
  _ValueAxisPainter({required this.geometry, required this.labelStyle});

  final _PlotGeometry geometry;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    for (final value in geometry.gridValues) {
      final painter = TextPainter(
        text: TextSpan(text: Money.compact(value), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(
          // Right-aligned against the plot, with a hair of breathing room.
          size.width - painter.width - 6,
          (geometry.yFor(value) - painter.height / 2).clamp(
            0.0,
            size.height - painter.height,
          ),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_ValueAxisPainter old) =>
      old.geometry.axisMax != geometry.axisMax ||
      old.geometry.axisMin != geometry.axisMin ||
      old.geometry.step != geometry.step ||
      old.labelStyle != labelStyle;
}

/// The figures for the selected bar.
///
/// Fixed height on purpose: selecting and clearing must not shove the rest of
/// the screen up and down while a finger is dragging across the chart.
class _BucketDetailPanel extends StatelessWidget {
  const _BucketDetailPanel({required this.bucket, required this.idleSummary});

  final ProfitBucket? bucket;
  final String idleSummary;

  /// Two lines of detail: at one line the figures ran off the end as
  /// "8h 00m · $…", which hid the hourly rate — the number the whole app is
  /// about.
  static const _height = 62.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final current = bucket;

    return SizedBox(
      height: _height,
      child: current == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                idleSummary,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.shiftCount == 0
                            ? current.detailLabel
                            : '${current.detailLabel} · ${current.shiftCount} '
                                  '${current.shiftCount == 1 ? 'shift' : 'shifts'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        current.shiftCount == 0
                            ? 'No shifts'
                            : 'Earned ${Money.cents(current.summary.gross)} · '
                                  'Costs ${Money.cents(current.summary.totalExpenses)} · '
                                  '${Money.hours(current.summary.hours)} · '
                                  '${Money.cents(current.summary.netPerHour)}/hr',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: tabularFigures,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  Money.cents(current.netProfit),
                  style: textTheme.titleMedium?.copyWith(
                    // A losing bucket must not be printed in the profit colour.
                    color: current.netProfit < 0
                        ? colors.error
                        : colors.primary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({
    required this.color,
    required this.label,
    required this.line,
  });

  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: line ? 14 : 10,
        height: line ? 3 : 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(line ? 99 : 3),
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

class _PeriodProfitPainter extends CustomPainter {
  _PeriodProfitPainter({
    required this.values,
    required this.previous,
    required this.geometry,
    required this.palette,
    required this.selectedIndex,
    required this.style,
    required this.peakLabelStyle,
    required this.valueLabelStyle,
  });

  final List<double> values;
  final List<double> previous;
  final _PlotGeometry geometry;
  final ChartPalette palette;
  final int? selectedIndex;
  final ProfitChartStyle style;

  /// For the biggest number on the chart, in either direction.
  final TextStyle peakLabelStyle;

  /// For every other bucket.
  final TextStyle valueLabelStyle;

  static const _radius = 4.0;

  /// Finmate's rod width. Wider than this and a week of bars reads as a block
  /// of colour rather than a series.
  static const _maxBarWidth = 12.0;

  /// The curve tension fl_chart applies at `curveSmoothness: 0.3`.
  static const _smoothness = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final slot = size.width / values.length;
    final baselineY = geometry.baselineY;

    // Drawn first so the selection sits behind every mark.
    _drawSelection(canvas, size, slot);
    _drawGrid(canvas, size, baselineY);

    if (style == ProfitChartStyle.line) {
      _drawLines(canvas, size, slot);
      return;
    }
    _drawBars(canvas, size, slot, baselineY);
  }

  /// Marks the selected bucket in the line view.
  ///
  /// Bars deliberately get nothing here. A filled column behind the selected
  /// bar — at any width, tint or opacity — reads as a drop shadow on the bar
  /// rather than as a selection, so the bar outlines itself in [_drawBars]
  /// instead and nothing is painted behind it.
  void _drawSelection(Canvas canvas, Size size, double slot) {
    final index = selectedIndex;
    if (index == null || style != ProfitChartStyle.line) return;
    final centre = index * slot + slot / 2;
    canvas.drawLine(
      Offset(centre, geometry.top),
      Offset(centre, geometry.top + geometry.height),
      Paint()
        ..color = palette.grid
        ..strokeWidth = 1,
    );
  }

  /// Horizontal rules only. Vertical ones would fence off each bucket and the
  /// bars already do that job.
  void _drawGrid(Canvas canvas, Size size, double baselineY) {
    final grid = Paint()
      ..color = palette.grid.withValues(alpha: .34)
      ..strokeWidth = 1;
    for (final value in geometry.gridValues) {
      if (value == 0) continue;
      final y = geometry.yFor(value);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Zero is the line every bar is measured from, so it stays solid while the
    // rest of the grid recedes.
    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      Paint()
        ..color = palette.grid
        ..strokeWidth = 1,
    );
  }

  /// How the rods in one slot are laid out. Shared with the selection so the
  /// highlight is sized against the bars it is behind rather than the slot.
  ({bool grouped, double gap, double width}) _barMetrics(double slot) {
    // Below this a pair of rods plus their gaps is thinner than a finger, so
    // the comparison falls back to a track behind the current bar.
    final grouped = previous.isNotEmpty && slot >= 26;
    final gap = slot < 12 ? 1.0 : 2.0;
    // Capped rather than filling the slot: a week's seven buckets across a
    // phone gives each one ~43pt, and a bar that wide reads as a block of
    // colour instead of a value.
    return (
      grouped: grouped,
      gap: gap,
      width: grouped
          ? ((slot - gap * 3) / 2).clamp(3.0, _maxBarWidth)
          : (slot - gap * 2).clamp(2.0, _maxBarWidth),
    );
  }

  void _drawBars(Canvas canvas, Size size, double slot, double baselineY) {
    final (grouped: grouped, gap: gap, width: barWidth) = _barMetrics(slot);
    // Collected as they are drawn so the labels can hang off the rectangle the
    // bar actually occupies rather than off its value: a bucket under the
    // minimum visible height is taller than its number says.
    final bars = <int, Rect>{};

    for (var i = 0; i < values.length; i++) {
      final centre = i * slot + slot / 2;
      final hasPrevious = i < previous.length && previous[i] != 0;

      if (grouped) {
        // Side by side, current first — the Finmate grouping.
        if (hasPrevious) {
          _drawBar(
            canvas,
            centre: centre + barWidth / 2 + gap / 2,
            width: barWidth,
            value: previous[i],
            baselineY: baselineY,
            color: palette.context.withValues(alpha: .55),
          );
        }
        if (values[i] != 0) {
          bars[i] = _drawBar(
            canvas,
            centre: hasPrevious ? centre - barWidth / 2 - gap / 2 : centre,
            width: barWidth,
            value: values[i],
            baselineY: baselineY,
            color: values[i] < 0 ? palette.negative : palette.positive,
            selected: i == selectedIndex,
          );
        }
      } else {
        // Prior period sits behind and wider, reading as a track rather than a
        // competing bar. When space is tight it cannot afford to be wider.
        if (hasPrevious) {
          _drawBar(
            canvas,
            centre: centre,
            width: slot < 12 ? barWidth : barWidth * 1.5,
            value: previous[i],
            baselineY: baselineY,
            color: palette.context.withValues(alpha: .38),
          );
        }
        if (values[i] != 0) {
          bars[i] = _drawBar(
            canvas,
            centre: centre,
            width: barWidth,
            value: values[i],
            baselineY: baselineY,
            color: values[i] < 0 ? palette.negative : palette.positive,
            selected: i == selectedIndex,
          );
        }
      }
    }

    _paintLabels(canvas, size, [
      for (final entry in bars.entries)
        (
          index: entry.key,
          value: values[entry.key],
          centre: entry.value.center.dx,
          // A label hangs off the data end of its own bar, so a loss reads
          // downwards the way the bar does.
          anchorY: values[entry.key] < 0 ? entry.value.bottom : entry.value.top,
          below: values[entry.key] < 0,
        ),
    ], obstacles: bars);
  }

  /// Returns the rectangle the bar occupies, which is not always the one its
  /// value implies — see the minimum height below.
  Rect _drawBar(
    Canvas canvas, {
    required double centre,
    required double width,
    required double value,
    required double baselineY,
    required Color color,
    bool selected = false,
  }) {
    // A small value next to a large peak would otherwise round to a sliver a
    // couple of pixels tall — which matters most for a loss day, the exact bar
    // the driver needs to notice.
    const minVisible = 6.0;
    final end = geometry.yFor(value);
    final height = math.max((end - baselineY).abs(), minVisible);
    final rect = value < 0
        ? Rect.fromLTWH(centre - width / 2, baselineY, width, height)
        : Rect.fromLTWH(centre - width / 2, baselineY - height, width, height);

    // Rounded only at the data end; the baseline end stays square so the bar
    // is visibly anchored to zero.
    const radius = Radius.circular(_radius);
    final rrect = value < 0
        ? RRect.fromRectAndCorners(
            rect,
            bottomLeft: radius,
            bottomRight: radius,
          )
        : RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius);
    canvas.drawRRect(rrect, Paint()..color = color);

    // Selection is drawn on the bar, never behind it: a ring around the mark
    // itself cannot be mistaken for a shadow the way a filled column can.
    if (!selected) return rect;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect.inflate(3),
        topLeft: value < 0 ? Radius.zero : const Radius.circular(_radius + 3),
        topRight: value < 0 ? Radius.zero : const Radius.circular(_radius + 3),
        bottomLeft: value < 0
            ? const Radius.circular(_radius + 3)
            : Radius.zero,
        bottomRight: value < 0
            ? const Radius.circular(_radius + 3)
            : Radius.zero,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // The ring is decoration around the bar; the bar itself is still the rect
    // a label should measure against.
    return rect;
  }

  void _drawLines(Canvas canvas, Size size, double slot) {
    if (previous.isNotEmpty) {
      _drawLineSeries(canvas, size, slot, series: previous, prior: true);
    }
    _drawLineSeries(canvas, size, slot, series: values, prior: false);
  }

  void _drawLineSeries(
    Canvas canvas,
    Size size,
    double slot, {
    required List<double> series,
    required bool prior,
  }) {
    final count = math.min(series.length, values.length);
    if (count == 0) return;

    final points = [
      for (var i = 0; i < count; i++)
        Offset(i * slot + slot / 2, geometry.yFor(series[i])),
    ];
    final path = _curveThrough(points);
    final plot = Rect.fromLTWH(0, geometry.top, size.width, geometry.height);

    // The gradient fill is what makes the line read as a quantity rather than
    // a squiggle — the area under it is the money.
    final fill = Path.from(path)
      ..lineTo(points.last.dx, geometry.baselineY)
      ..lineTo(points.first.dx, geometry.baselineY)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = _seriesShader(
          plot,
          prior: prior,
          opacity: prior ? .10 : .20,
        ),
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = _seriesShader(plot, prior: prior)
        ..style = PaintingStyle.stroke
        ..strokeWidth = prior ? 2 : 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (prior) return;

    // Finmate hides the dots; a loss point still gets one, because a segment
    // dipping below zero is the single most important thing on this chart and
    // it must not rest on the line's colour alone.
    for (var i = 0; i < count; i++) {
      final selected = i == selectedIndex;
      if (series[i] >= 0 && !selected) continue;
      final color = series[i] < 0 ? palette.negative : palette.positive;
      canvas.drawCircle(points[i], selected ? 5 : 3.5, Paint()..color = color);
      if (selected) {
        canvas.drawCircle(
          points[i],
          7,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    _paintLabels(canvas, size, [
      for (var i = 0; i < count; i++)
        if (series[i] != 0)
          (
            index: i,
            value: series[i],
            centre: points[i].dx,
            // Clear of the dot drawn on a loss or a selection, not just of the
            // line.
            anchorY: series[i] < 0 ? points[i].dy + 5 : points[i].dy - 5,
            below: series[i] < 0,
          ),
    ]);
  }

  void _paintLabels(
    Canvas canvas,
    Size size,
    List<ProfitLabelAnchor> anchors, {
    Map<int, Rect> obstacles = const {},
  }) {
    for (final label in layOutProfitLabels(
      anchors: anchors,
      size: size,
      baselineY: geometry.baselineY,
      peakStyle: peakLabelStyle,
      valueStyle: valueLabelStyle,
      obstacles: obstacles,
      selectedIndex: selectedIndex,
    )) {
      label.painter.paint(canvas, label.rect.topLeft);
    }
  }

  /// One colour above zero and another below it, switched with a hard stop on
  /// the baseline.
  ///
  /// Colouring the whole series by "does it contain a loss" painted a week
  /// with six good days and one bad one entirely red. This way the curve turns
  /// at exactly the point the driver started losing money.
  ///
  /// With [opacity] the two halves also fade out towards the baseline, which
  /// is the area fill: densest at the extremes, gone at zero.
  Shader _seriesShader(Rect plot, {required bool prior, double? opacity}) {
    final above = prior ? palette.context : palette.positive;
    final below = prior ? palette.context : palette.negative;
    // Half a stroke below the baseline, so a day that earned exactly nothing
    // draws in the profit colour rather than being reported as a loss.
    const zeroTolerance = 1.5;
    final stop = plot.height <= 0
        ? 1.0
        : ((geometry.baselineY + zeroTolerance - plot.top) / plot.height).clamp(
            0.0,
            1.0,
          );

    Color shade(Color color, double alpha) =>
        color.withValues(alpha: prior && opacity == null ? .58 : alpha);

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: opacity == null
          ? [shade(above, 1), shade(above, 1), shade(below, 1), shade(below, 1)]
          : [
              above.withValues(alpha: opacity),
              above.withValues(alpha: 0),
              below.withValues(alpha: 0),
              below.withValues(alpha: opacity),
            ],
      stops: [0, stop, stop, 1],
    ).createShader(plot);
  }

  /// A cubic through every point at Finmate's `curveSmoothness: 0.3`.
  ///
  /// Each segment's control points are held inside that segment's own vertical
  /// range. Left free, a cubic overshoots after a sharp peak: the Friday-to-
  /// Saturday drop dipped the curve below zero and drew a loss on a day the
  /// driver simply did not work. A chart may not invent money it does not have.
  Path _curveThrough(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path;

    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final before = i == 0 ? current : points[i - 1];
      final after = i + 2 < points.length ? points[i + 2] : next;

      final low = math.min(current.dy, next.dy);
      final high = math.max(current.dy, next.dy);
      double hold(double y) => y.clamp(low, high);

      path.cubicTo(
        current.dx + (next.dx - before.dx) * _smoothness,
        hold(current.dy + (next.dy - before.dy) * _smoothness),
        next.dx - (after.dx - current.dx) * _smoothness,
        hold(next.dy - (after.dy - current.dy) * _smoothness),
        next.dx,
        next.dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_PeriodProfitPainter old) =>
      old.values != values ||
      old.previous != previous ||
      old.geometry.axisMax != geometry.axisMax ||
      old.geometry.axisMin != geometry.axisMin ||
      old.selectedIndex != selectedIndex ||
      old.style != style ||
      old.palette.positive != palette.positive ||
      old.palette.negative != palette.negative ||
      old.palette.context != palette.context ||
      old.palette.grid != palette.grid;
}

/// A bucket's value and the mark its figure has to stand clear of: [centre] is
/// the middle of the mark, [anchorY] the edge the label hangs off — a bar's
/// data end, or a point on the line — and [below] says the label goes under it,
/// which is how losses read.
typedef ProfitLabelAnchor = ({
  int index,
  double value,
  double centre,
  double anchorY,
  bool below,
});

/// A figure and the box it was given, ready to paint.
typedef ProfitLabel = ({
  int index,
  String text,
  Rect rect,
  TextPainter painter,
});

/// Places a number on every bucket, biggest first.
///
/// Priority is what makes this survive a 31-day month on a phone: at ~10pt per
/// slot there is no room for 31 figures, so a label that would collide with one
/// already standing is dropped. The largest values are placed first and
/// therefore always win, which is the opposite of the naive left-to-right pass
/// that labels the first few days and gives up before the best one.
///
/// [obstacles] are the bars themselves, keyed by bucket: a label may sit over
/// empty plot, but printing it across a neighbouring bar reads as a rendering
/// fault. A bar never obstructs its own label.
///
/// Separate from the painter because this is the part with the arithmetic in
/// it, and a canvas is a poor thing to make assertions against.
@visibleForTesting
List<ProfitLabel> layOutProfitLabels({
  required List<ProfitLabelAnchor> anchors,
  required Size size,
  required double baselineY,
  required TextStyle peakStyle,
  required TextStyle valueStyle,
  Map<int, Rect> obstacles = const {},
  int? selectedIndex,
}) {
  // Between two labels, and between a label and the mark it belongs to.
  const gap = 5.0;
  const clearance = 3.0;

  final ordered = [...anchors]
    ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  final placed = <ProfitLabel>[];

  for (var rank = 0; rank < ordered.length; rank++) {
    final anchor = ordered[rank];
    // While a bucket is selected the panel underneath carries its figures in
    // full, so its own label would be a second, competing answer. The rest stay
    // put — the neighbours are exactly what the selection is compared against.
    if (anchor.index == selectedIndex) continue;
    // A day the driver did not work is not a $0 result worth printing, and a
    // row of them would be several numbers that say nothing.
    if (anchor.value == 0) continue;

    final text = Money.whole(anchor.value);
    // Only the biggest number on the chart keeps the emphasis the single peak
    // label used to have.
    final painter = TextPainter(
      text: TextSpan(text: text, style: rank == 0 ? peakStyle : valueStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final left = (anchor.centre - painter.width / 2)
        .clamp(0.0, math.max(0.0, size.width - painter.width))
        .toDouble();
    var top = anchor.below
        ? anchor.anchorY + clearance
        : anchor.anchorY - clearance - painter.height;
    // A loss that reaches the bottom of the plot has nowhere below it to print;
    // the empty half-slot above the baseline always has room.
    if (anchor.below && top + painter.height > size.height) {
      top = baselineY - clearance - painter.height;
    }
    top = top
        .clamp(0.0, math.max(0.0, size.height - painter.height))
        .toDouble();

    final rect = Rect.fromLTWH(left, top, painter.width, painter.height);
    final collides =
        placed.any((other) => other.rect.overlaps(rect.inflate(gap))) ||
        obstacles.entries.any(
          (bar) => bar.key != anchor.index && bar.value.overlaps(rect),
        );
    if (collides) continue;

    placed.add((index: anchor.index, text: text, rect: rect, painter: painter));
  }
  return placed;
}
