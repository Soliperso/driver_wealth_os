import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../domain/shift.dart';

class ShiftResultScreen extends StatefulWidget {
  const ShiftResultScreen({
    super.key,
    required this.shift,
    required this.onSave,
    this.saveLabel = 'Save to Today',
  });
  final Shift shift;
  final VoidCallback onSave;
  final String saveLabel;

  @override
  State<ShiftResultScreen> createState() => _ShiftResultScreenState();
}

class _ShiftResultScreenState extends State<ShiftResultScreen> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final shift = widget.shift;
    final colors = Theme.of(context).colorScheme;
    return SoftScaffold(
      title: 'Shift result',
      body: PageFrame(
        maxWidth: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassSurface(
                elevation: Elevation.hero,
                tint:
                    (shift.netProfit < 0
                            ? colors.errorContainer
                            : colors.primaryContainer)
                        .withValues(alpha: .82),
                padding: const EdgeInsets.all(Space.xl),
                child: Column(
                  children: [
                    SoftIcon(
                      shift.netProfit < 0
                          ? Icons.trending_down_rounded
                          : Icons.done_rounded,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'TRUE PROFIT',
                      style: TextStyle(
                        color: colors.primary,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Money.cents(shift.netProfit),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${Money.percent(shift.keepRate)} keep rate',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 520;
                  return Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          label: 'Net / hour',
                          value: Money.cents(shift.netPerHour),
                          compact: compact,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Metric(
                          label: 'Net / mile',
                          value: Money.cents(shift.netPerMile),
                          compact: compact,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Metric(
                          label: 'Total costs',
                          value: Money.cents(shift.totalExpenses),
                          compact: compact,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              GlassSurface(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Calculation',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _CalculationRow(
                      label: 'Gross earnings',
                      value: shift.gross,
                    ),
                    _CalculationRow(
                      label: 'Fuel, tolls & parking',
                      value: -shift.directExpenses,
                    ),
                    _CalculationRow(
                      label:
                          'Vehicle wear (${Money.number(shift.miles)} mi × '
                          '${Money.cents(shift.vehicleCostPerMile)})',
                      value: -shift.vehicleCost,
                    ),
                    const Divider(height: 24),
                    _CalculationRow(
                      label: 'True profit',
                      value: shift.netProfit,
                      emphasized: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GlassSurface(
                padding: const EdgeInsets.all(22),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SoftIcon(Icons.auto_awesome_rounded),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your next move',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _insight(shift),
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : widget.saveLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _insight(Shift shift) {
    if (shift.keepRate >= .75) {
      return 'Strong shift. You kept at least 75¢ of every dollar—use this as a benchmark for future shifts.';
    }
    if (shift.netPerHour >= 25) {
      return 'Your hourly profit is healthy. Review vehicle and direct costs to raise your keep rate next time.';
    }
    return 'This shift earned less than \$25 net per hour. Compare its time and mileage with your next shift before repeating it.';
  }

  void _save() {
    if (_saving) return;
    setState(() => _saving = true);
    widget.onSave();
    Navigator.of(context).pop();
  }
}

class _CalculationRow extends StatelessWidget {
  const _CalculationRow({
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
    final prefix = value < 0 ? '−' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(
            prefix.isEmpty ? Money.cents(value) : Money.negated(value),
            style: style?.copyWith(fontFeatures: tabularFigures),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.compact,
  });
  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) => GlassSurface(
    elevation: Elevation.flat,
    padding: EdgeInsets.symmetric(
      horizontal: compact ? Space.md : Space.lg,
      vertical: compact ? Space.lg : Space.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? Theme.of(context).textTheme.bodySmall
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
        ),
        SizedBox(height: compact ? 5 : 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style:
                (compact
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}
