import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/presentation/add_shift_screen.dart';

class ShiftDetailScreen extends StatefulWidget {
  const ShiftDetailScreen({
    super.key,
    required this.shift,
    required this.onUpdated,
    required this.onDeleted,
  });

  final Shift shift;
  final ValueChanged<Shift> onUpdated;
  final ValueChanged<String> onDeleted;

  @override
  State<ShiftDetailScreen> createState() => _ShiftDetailScreenState();
}

class _ShiftDetailScreenState extends State<ShiftDetailScreen> {
  late Shift _shift = widget.shift;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // An unprofitable shift is the thing the driver most needs to notice, so
    // it must not share the reassuring tint of a profitable one.
    final isLoss = _shift.netProfit < 0;
    return SoftScaffold(
      title: 'Shift details',
      body: PageFrame(
        maxWidth: 680,
        child: ListView(
          children: [
            GlassSurface(
              key: ValueKey(
                'shift-detail-${isLoss ? 'loss' : 'profit'}-${_shift.id}',
              ),
              padding: const EdgeInsets.all(22),
              tint: (isLoss ? colors.errorContainer : colors.primaryContainer)
                  .withValues(alpha: .82),
              child: Row(
                children: [
                  PlatformLogo(platform: _shift.platform, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shift.platform.displayName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _date(_shift.completedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'True profit',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        Money.cents(_shift.netProfit),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Profit breakdown',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DetailRow(label: 'Gross earnings', value: _shift.gross),
                  _DetailRow(
                    label: 'Fuel, tolls & parking',
                    value: -_shift.directExpenses,
                  ),
                  _DetailRow(label: 'Vehicle wear', value: -_shift.vehicleCost),
                  const Divider(height: 24),
                  _DetailRow(
                    label: 'True profit',
                    value: _shift.netProfit,
                    emphasized: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Expanded(
                    child: _SmallMetric(
                      label: 'Net / hour',
                      value: Money.cents(_shift.netPerHour),
                    ),
                  ),
                  Expanded(
                    child: _SmallMetric(
                      label: 'Net / mile',
                      value: Money.cents(_shift.netPerMile),
                    ),
                  ),
                  Expanded(
                    child: _SmallMetric(
                      label: 'Keep rate',
                      value: Money.percent(_shift.keepRate),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _edit, child: const Text('Edit shift')),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete shift'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddShiftScreen(
          initialShift: _shift,
          onSave: (updated) {
            widget.onUpdated(updated);
            if (mounted) setState(() => _shift = updated);
          },
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this shift?'),
        content: const Text(
          'This removes the shift from your history and recalculates your totals.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onDeleted(_shift.id);
    Navigator.of(context).pop();
  }

  static String _date(DateTime date) =>
      '${date.month}/${date.day}/${date.year} at ${_time(date)}';

  static String _time(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final double value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value < 0 ? Money.negated(value) : Money.cents(value),
            style: style?.copyWith(fontFeatures: tabularFigures),
          ),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}
