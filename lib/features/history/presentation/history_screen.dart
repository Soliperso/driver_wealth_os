import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../shifts/domain/period_analytics.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_summary.dart';
import 'shift_detail_screen.dart';
import 'cost_breakdown_section.dart';
import 'history_analytics_sections.dart';
import 'period_hero_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.shifts,
    required this.onAddShift,
    required this.onShiftUpdated,
    required this.onShiftDeleted,
  });

  final List<Shift> shifts;
  final VoidCallback onAddShift;
  final ValueChanged<Shift> onShiftUpdated;
  final ValueChanged<String> onShiftDeleted;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  ReportPeriod _period = ReportPeriod.week;
  late DateTime _anchor;
  late DateTime _now;

  late List<Shift> _ordered;
  late List<Shift> _periodShifts;
  late PeriodPerformance _performance;
  var _showAllShifts = false;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _anchor = _now;
    _recompute();
  }

  @override
  void didUpdateWidget(HistoryScreen old) {
    super.didUpdateWidget(old);
    // The shift list is mutated in place upstream, so neither its identity nor
    // its length reliably signals an edit. A parent rebuild is the signal.
    _recompute();
  }

  /// Every figure on this screen is a full scan of the shift list, so it is
  /// computed once per data change and held — never inside [build].
  void _recompute() {
    final unique = <String, Shift>{};
    for (final shift in widget.shifts) {
      unique.putIfAbsent(shift.id, () => shift);
    }
    _ordered = unique.values.toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    _performance = PeriodAnalytics.of(_ordered, _period, _anchor);
    _periodShifts = _ordered
        .where((shift) => _performance.range.contains(shift.completedAt))
        .toList();
  }

  void _changePeriod(ReportPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _showAllShifts = false;
      _recompute();
    });
  }

  void _step(int direction) {
    final range = PeriodRange.containing(_anchor, _period);
    final target = direction < 0 ? range.previous() : range.next();
    setState(() {
      _anchor = target.start;
      _showAllShifts = false;
      _recompute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayedShifts = _showAllShifts ? _ordered : _periodShifts;
    final shiftsNeedingCostReview = _periodShifts
        .where(
          (shift) =>
              shift.source == ShiftSource.imported && !shift.costsReviewed,
        )
        .toList();
    return SoftScaffold(
      title: 'History',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Add shift',
            onPressed: widget.onAddShift,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
      ],
      body: PageFrame(
        child: _ordered.isEmpty
            ? _EmptyHistory(onAddShift: widget.onAddShift)
            : ListView(
                children: [
                  PeriodHeroCard(
                    performance: _performance,
                    period: _period,
                    now: _now,
                    onPeriodChanged: _changePeriod,
                    onStep: _step,
                  ),
                  if (shiftsNeedingCostReview.isNotEmpty) ...[
                    const SizedBox(height: Space.md),
                    _CostReviewNotice(
                      count: shiftsNeedingCostReview.length,
                      onReview: () => _openShift(shiftsNeedingCostReview.first),
                    ),
                  ],
                  const SizedBox(height: Space.md),
                  PeriodPerformanceSection(performance: _performance),
                  const SizedBox(height: Space.md),
                  CostBreakdownSection(summary: _performance.summary),
                  PlatformPerformanceSection(shifts: _periodShifts),
                  const SizedBox(height: Space.md),
                  EarningsDnaSection(shifts: _periodShifts),
                  const SizedBox(height: 26),
                  if (displayedShifts.isNotEmpty) ...[
                    Text(
                      _showAllShifts ? 'All shifts' : _periodShiftTitle(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    // Grouped by day, because a bare list of shifts makes the
                    // reader add up their own Tuesday. The header carries the
                    // day's net so the list answers the same question the
                    // chart above it does.
                    for (final day in _byDay(displayedShifts)) ...[
                      _DayHeader(date: day.date, shifts: day.shifts),
                      const SizedBox(height: Space.sm),
                      for (final shift in day.shifts) ...[
                        _HistoryRow(
                          shift: shift,
                          onTap: () => _openShift(shift),
                        ),
                        const SizedBox(height: Space.sm),
                      ],
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                  if (_ordered.length > _periodShifts.length) ...[
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _showAllShifts = !_showAllShifts),
                        child: Text(
                          _showAllShifts
                              ? 'Show selected period'
                              : 'View all shifts',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.bottomNavClearance),
                ],
              ),
      ),
    );
  }

  /// Splits an already date-sorted list into calendar days, newest first.
  static List<({DateTime date, List<Shift> shifts})> _byDay(
    List<Shift> shifts,
  ) {
    final days = <DateTime, List<Shift>>{};
    for (final shift in shifts) {
      final at = shift.completedAt;
      days
          .putIfAbsent(DateTime(at.year, at.month, at.day), () => [])
          .add(shift);
    }
    return [
      for (final entry in days.entries) (date: entry.key, shifts: entry.value),
    ];
  }

  String _periodShiftTitle() {
    if (!_performance.range.isCurrent(_now)) {
      return 'Shifts · ${_performance.range.label(_now)}';
    }
    return switch (_period) {
      ReportPeriod.day => 'Shifts today',
      ReportPeriod.week => 'Shifts this week',
      ReportPeriod.month => 'Shifts this month',
      ReportPeriod.year => 'Shifts this year',
    };
  }

  void _openShift(Shift shift) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShiftDetailScreen(
          shift: shift,
          onUpdated: widget.onShiftUpdated,
          onDeleted: widget.onShiftDeleted,
        ),
      ),
    );
  }
}

class _CostReviewNotice extends StatelessWidget {
  const _CostReviewNotice({required this.count, required this.onReview});

  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('cost-review-notice'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .38)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 18,
            color: colors.onTertiaryContainer,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              count == 1
                  ? 'Review costs for 1 imported shift'
                  : 'Review costs for $count imported shifts',
              maxLines: 2,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('review-imported-costs'),
            onPressed: onReview,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(44, 40),
            ),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.onAddShift});

  final VoidCallback onAddShift;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height - 210,
    width: double.infinity,
    child: GlassSurface(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 60,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'No shifts yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Your completed shifts will appear here with their true-profit details.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAddShift,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add first shift'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The date, and what that whole day came to.
///
/// The day's net is the figure the driver is scanning for; without it the list
/// is a stack of individual shifts that they have to total in their head.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.shifts});

  final DateTime date;
  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final summary = ShiftSummary.from(shifts);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(date).inDays;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              switch (difference) {
                0 => 'Today',
                1 => 'Yesterday',
                _ => DateFormat(
                  date.year == now.year ? 'EEEE, MMM d' : 'EEE, MMM d, y',
                  'en_US',
                ).format(date),
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Text(
            '${shifts.length} ${shifts.length == 1 ? 'shift' : 'shifts'}',
            style: textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: Space.sm),
          Text(
            Money.cents(summary.netProfit),
            style: textTheme.labelLarge?.copyWith(
              // A losing day must not be printed in the profit colour.
              color: summary.netProfit < 0 ? colors.error : colors.primary,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.shift, required this.onTap});

  final Shift shift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      elevation: Elevation.flat,
      radius: 14,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('history-shift-${shift.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: 10,
            ),
            child: Row(
              children: [
                PlatformLogo(platform: shift.platform, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift.platform.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // The date moved up to the day header, so the row can
                        // spend that space on when in the day it ran and how
                        // long it took. Miles, gross and keep rate are one tap
                        // away in the detail screen — stacking them here made
                        // every row a paragraph to be read rather than a line
                        // to be scanned.
                        '${DateFormat('h:mm a', 'en_US').format(shift.completedAt)} · '
                        '${Money.hours(shift.hours)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.cents(shift.netProfit),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        // A losing shift must not use the profit colour.
                        color: shift.netProfit < 0
                            ? colors.error
                            : colors.primary,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    Text(
                      // "Net" only restated the colour-coded figure above it.
                      // The hourly rate is what makes two shifts comparable.
                      shift.hours > 0
                          ? '${Money.cents(shift.netPerHour)}/hr'
                          : 'Net',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: Space.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
