import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_summary.dart';
import 'shift_detail_screen.dart';
import 'history_analytics_sections.dart';

class HistoryScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final uniqueShifts = <String, Shift>{};
    for (final shift in shifts) {
      uniqueShifts.putIfAbsent(shift.id, () => shift);
    }
    final orderedShifts = uniqueShifts.values.toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    return SoftScaffold(
      title: 'History',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Add shift',
            onPressed: onAddShift,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
      ],
      body: PageFrame(
        child: orderedShifts.isEmpty
            ? _EmptyHistory(onAddShift: onAddShift)
            : _HistoryList(
                shifts: orderedShifts,
                onShiftUpdated: onShiftUpdated,
                onShiftDeleted: onShiftDeleted,
              ),
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

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.shifts,
    required this.onShiftUpdated,
    required this.onShiftDeleted,
  });

  final List<Shift> shifts;
  final ValueChanged<Shift> onShiftUpdated;
  final ValueChanged<String> onShiftDeleted;

  @override
  Widget build(BuildContext context) {
    final summary = ShiftSummary.from(shifts);
    return ListView(
      children: [
        GlassSurface(
          elevation: Elevation.hero,
          padding: const EdgeInsets.all(Space.xl),
          tint: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: .82),
          child: Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: 'Total true profit',
                  value: Money.cents(summary.netProfit),
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(
                child: _SummaryMetric(
                  label: 'Completed shifts',
                  value: '${summary.shiftCount}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        WeeklyPerformanceSection(shifts: shifts),
        const SizedBox(height: 16),
        EarningsDnaSection(shifts: shifts),
        const SizedBox(height: 26),
        Text('All shifts', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final shift in shifts) ...[
          _HistoryRow(
            shift: shift,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ShiftDetailScreen(
                  shift: shift,
                  onUpdated: onShiftUpdated,
                  onDeleted: onShiftDeleted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 82),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.shift, required this.onTap});

  final Shift shift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassSurface(
    elevation: Elevation.flat,
    padding: EdgeInsets.zero,
    child: Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: ValueKey('history-shift-${shift.id}'),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: PlatformLogo(platform: shift.platform, size: 44),
        title: Text(
          shift.platform.displayName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_date(shift.completedAt)} · ${shift.hours.toStringAsFixed(1)} hrs',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Money.cents(shift.netProfit),
              style: TextStyle(
                // A losing shift must not be printed in the profit colour.
                color: shift.netProfit < 0
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    ),
  );

  static String _date(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
