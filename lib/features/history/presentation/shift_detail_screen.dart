import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../settings/domain/driving_costs.dart';
import '../../settings/domain/measurement_units.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/presentation/add_shift_screen.dart';

class ShiftDetailScreen extends StatefulWidget {
  const ShiftDetailScreen({
    super.key,
    required this.shift,
    required this.onUpdated,
    required this.onDeleted,
    this.units = const MeasurementUnits(),
    this.drivingCosts = const DrivingCosts(),
  });

  final Shift shift;
  final ValueChanged<Shift> onUpdated;
  final ValueChanged<String> onDeleted;
  final MeasurementUnits units;

  /// Carried only so the edit screen can price fuel; this screen shows what
  /// the shift itself recorded, never today's rates.
  final DrivingCosts drivingCosts;

  @override
  State<ShiftDetailScreen> createState() => _ShiftDetailScreenState();
}

class _ShiftDetailScreenState extends State<ShiftDetailScreen> {
  late Shift _shift = widget.shift;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final units = widget.units;
    // An unprofitable shift is the thing the driver most needs to notice, so
    // it must not share the reassuring tint of a profitable one.
    final isLoss = _shift.netProfit < 0;
    return SoftScaffold(
      title: 'Session details',
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
                          _shift.platformLabel,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          // The history row now carries only time and
                          // duration, so this is where distance has to land.
                          '${_date(_shift.completedAt)} · '
                          '${Money.hours(_shift.hours)} · '
                          '${units.distanceLabel(_shift.miles, decimals: 0)}',
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
                        units.cents(_shift.netProfit),
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
                  // One line per app, but only when there is more than one:
                  // on a single-app shift the breakdown would just restate the
                  // total under a different name.
                  if (_shift.isMultiApp)
                    for (final platform in _shift.platformsByEarnings)
                      _DetailRow(
                        key: ValueKey('detail-earnings-${platform.id}'),
                        label: '${platform.displayName} earnings',
                        value: _shift.earnedOn(platform),
                        units: units,
                        muted: true,
                      ),
                  _DetailRow(
                    // Named as a total only once it is the sum of lines above.
                    label: _shift.isMultiApp
                        ? 'Gross earnings (total)'
                        : 'Gross earnings',
                    value: _shift.gross,
                    units: units,
                  ),
                  // Costs stay whole. They were spent once, by one car, and
                  // splitting them per app would invent a number nobody knows.
                  _DetailRow(
                    label: 'Fuel, tolls & parking',
                    value: -_shift.directExpenses,
                    units: units,
                  ),
                  _DetailRow(
                    label: 'Vehicle wear',
                    value: -_shift.vehicleCost,
                    units: units,
                  ),
                  const Divider(height: 24),
                  _DetailRow(
                    label: 'True profit',
                    value: _shift.netProfit,
                    units: units,
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
                      value: units.cents(_shift.netPerHour),
                    ),
                  ),
                  Expanded(
                    child: _SmallMetric(
                      label: 'Net / ${units.distance.singular}',
                      value: units.cents(_shift.netPerMile),
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
            FilledButton(onPressed: _edit, child: const Text('Edit session')),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete session'),
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
          units: widget.units,
          drivingCosts: widget.drivingCosts,
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
        title: const Text('Delete this session?'),
        content: const Text(
          'This removes the session from your history and recalculates your totals.',
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
    super.key,
    required this.label,
    required this.value,
    required this.units,
    this.emphasized = false,
    this.muted = false,
  });

  final String label;
  final double value;
  final MeasurementUnits units;
  final bool emphasized;

  /// A contributing line rather than a figure in its own right — the per-app
  /// earnings that add up to the gross directly beneath them.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = emphasized
        ? Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
        : muted
        ? Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value < 0 ? units.negated(value) : units.cents(value),
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
