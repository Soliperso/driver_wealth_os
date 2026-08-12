import 'package:flutter/material.dart';

import '../../../core/charts/goal_ring.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_analytics.dart';
import '../domain/freedom_goal.dart';

class FreedomScreen extends StatelessWidget {
  const FreedomScreen({
    super.key,
    required this.shifts,
    required this.goal,
    required this.onGoalChanged,
  });

  final List<Shift> shifts;
  final FreedomGoal? goal;
  final ValueChanged<FreedomGoal?> onGoalChanged;

  @override
  Widget build(BuildContext context) => SoftScaffold(
    title: 'Freedom',
    actions: goal == null
        ? null
        : [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => _editGoal(context),
                child: const Text('Edit'),
              ),
            ),
          ],
    body: PageFrame(
      maxWidth: 760,
      child: ListView(
        children: [
          if (goal == null)
            _GoalEmptyState(onCreate: () => _editGoal(context))
          else
            _GoalProgressCard(goal: goal!, shifts: shifts),
          const SizedBox(height: 16),
          _MoneyLeaksCard(shifts: shifts),
          const SizedBox(height: 92),
        ],
      ),
    ),
  );

  Future<void> _editGoal(BuildContext context) async {
    final result = await showModalBottomSheet<_GoalSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _GoalSheet(initialGoal: goal),
    );
    if (result == null) return;
    onGoalChanged(result.deleted ? null : result.goal);
  }
}

class _GoalEmptyState extends StatelessWidget {
  const _GoalEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 38),
    child: Column(
      children: [
        Icon(
          Icons.flag_outlined,
          size: 60,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        Text(
          'Choose what driving is building',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Create one goal and choose what percentage of positive true profit should count toward it.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        FilledButton(onPressed: onCreate, child: const Text('Create goal')),
      ],
    ),
  );
}

class _GoalProgressCard extends StatelessWidget {
  const _GoalProgressCard({required this.goal, required this.shifts});

  final FreedomGoal goal;
  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final progress = goal.progress(shifts);
    final ratio = (progress.amount / goal.targetAmount).clamp(0.0, 1.0);
    final complete = progress.remaining <= 0;
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      elevation: Elevation.hero,
      padding: const EdgeInsets.all(Space.xl),
      tint: complete
          ? colors.tertiaryContainer.withValues(alpha: .82)
          : colors.primaryContainer.withValues(alpha: .82),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                goal.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Space.xs),
              Text(
                complete
                    ? 'Goal complete'
                    : '${Money.percent(goal.allocationRate)} of positive profit allocated',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Space.gapXl,
          // Progress against a target is a ratio against a limit, so it reads
          // as a meter. The amount sits in the middle, so the value never has
          // to be inferred from the arc.
          Center(
            child: GoalRing(
              progress: ratio,
              centerValue: Money.whole(progress.amount),
              caption: 'of ${Money.whole(goal.targetAmount)}',
            ),
          ),
          Space.gapXl,
          Row(
            children: [
              Expanded(
                child: _GoalMetric(
                  label: 'From tracked profit',
                  value: Money.cents(progress.allocatedProfit),
                ),
              ),
              Expanded(
                child: _GoalMetric(
                  label: 'Remaining',
                  value: Money.cents(progress.remaining),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _projection(progress),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _projection(FreedomProgress progress) {
    if (progress.remaining <= 0) {
      return 'Your tracked allocation reached this goal.';
    }
    if (progress.projectedWeeks == null) {
      return 'Track positive profit on at least 2 separate days to estimate a completion date.';
    }
    return 'At your tracked allocation pace, approximately ${progress.projectedWeeks!.ceil()} weeks remain.';
  }
}

class _GoalMetric extends StatelessWidget {
  const _GoalMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _MoneyLeaksCard extends StatelessWidget {
  const _MoneyLeaksCard({required this.shifts});

  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final leaks = ShiftAnalytics.moneyLeaks(shifts);
    final recovery = ShiftAnalytics.totalPotentialRecovery(leaks);
    return GlassSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Money leaks',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (leaks.isNotEmpty)
                Text(
                  '\$${recovery.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            leaks.isEmpty
                ? 'No significant leaks detected from your tracked shifts.'
                : 'Estimated gap without counting any shift twice.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (leaks.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final leak in leaks.take(3)) ...[
              _LeakRow(leak: leak),
              if (leak != leaks.take(3).last) const Divider(height: 22),
            ],
          ],
        ],
      ),
    );
  }
}

class _LeakRow extends StatelessWidget {
  const _LeakRow({required this.leak});

  final MoneyLeak leak;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          Icons.south_east_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              leak.title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(leak.detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Text(
        '\$${leak.potentialRecovery.toStringAsFixed(2)}',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({required this.initialGoal});

  final FreedomGoal? initialGoal;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _target;
  late final TextEditingController _starting;
  late final TextEditingController _allocation;

  @override
  void initState() {
    super.initState();
    final goal = widget.initialGoal;
    _title = TextEditingController(text: goal?.title ?? '');
    _target = TextEditingController(text: _amount(goal?.targetAmount));
    _starting = TextEditingController(
      text: _amount(goal?.startingAmount, fallback: '0'),
    );
    _allocation = TextEditingController(
      text: goal == null ? '' : (goal.allocationRate * 100).toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _starting.dispose();
    _allocation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      8,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SafeArea(
      top: false,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.initialGoal == null ? 'Create goal' : 'Edit goal',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Goal name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a goal name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Target amount',
                  prefixText: '\$ ',
                ),
                validator: _positiveAmount,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _starting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Already saved',
                  prefixText: '\$ ',
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  final target = double.tryParse(_target.text);
                  if (parsed == null || parsed < 0) {
                    return 'Enter a valid amount';
                  }
                  if (target != null && parsed > target) {
                    return 'Starting amount cannot exceed the target';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _allocation,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Profit allocation',
                  suffixText: '%',
                  helperText:
                      'Percentage of future positive true profit assigned to this goal.',
                  helperMaxLines: 2,
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  return parsed == null || parsed <= 0 || parsed > 100
                      ? 'Enter a percentage from 1 to 100'
                      : null;
                },
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('Save goal')),
              if (widget.initialGoal != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _GoalSheetResult.deleted()),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Remove goal'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  String? _positiveAmount(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || parsed <= 0 || parsed > 10000000
        ? 'Enter an amount above \$0'
        : null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initialGoal;
    final goal = FreedomGoal(
      id: initial?.id ?? 'goal-${DateTime.now().microsecondsSinceEpoch}',
      title: _title.text.trim(),
      targetAmount: double.parse(_target.text),
      startingAmount: double.parse(_starting.text),
      allocationRate: double.parse(_allocation.text) / 100,
      createdAt: initial?.createdAt ?? DateTime.now(),
    );
    Navigator.of(context).pop(_GoalSheetResult.saved(goal));
  }

  static String _amount(double? value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  }
}

class _GoalSheetResult {
  const _GoalSheetResult.saved(this.goal) : deleted = false;
  const _GoalSheetResult.deleted() : goal = null, deleted = true;

  final FreedomGoal? goal;
  final bool deleted;
}
