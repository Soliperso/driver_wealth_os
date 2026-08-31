import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/editor_sheets.dart';
import '../../settings/domain/measurement_units.dart';
import '../domain/expense.dart';

/// Records one cost that is not attached to a shift.
///
/// Add and edit are the same sheet rather than two: the fields are identical,
/// and a driver correcting a figure should not have to relearn the form. The
/// only difference is the title and whether an id is minted.
class ExpenseEditorSheet extends StatefulWidget {
  const ExpenseEditorSheet({
    super.key,
    required this.units,
    this.initial,
    this.initialCategory,
    this.today,
  });

  /// The expense being edited, or null when adding a new one.
  final Expense? initial;

  /// Pre-selects a category when adding. Set when the sheet is opened from a
  /// category row, where the driver has already said what kind of cost this is.
  final ExpenseCategory? initialCategory;

  final MeasurementUnits units;

  /// Injectable wall clock, for the same reason History takes one: a test with
  /// fixed dates must not depend on the day it runs.
  final DateTime Function()? today;

  static Future<Expense?> show(
    BuildContext context, {
    required MeasurementUnits units,
    Expense? initial,
    ExpenseCategory? initialCategory,
    DateTime Function()? today,
  }) => showModalBottomSheet<Expense>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ExpenseEditorSheet(
      units: units,
      initial: initial,
      initialCategory: initialCategory,
      today: today,
    ),
  );

  @override
  State<ExpenseEditorSheet> createState() => _ExpenseEditorSheetState();
}

class _ExpenseEditorSheetState extends State<ExpenseEditorSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late ExpenseCategory _category;
  late DateTime _incurredOn;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amount = TextEditingController(
      text: initial == null ? '' : plainNumber(initial.amount),
    );
    _note = TextEditingController(text: initial?.note ?? '');
    _category =
        initial?.category ?? widget.initialCategory ?? ExpenseCategory.other;
    _incurredOn = initial?.incurredOn ?? (widget.today ?? DateTime.now)();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_amount.text.trim());
    // Zero is refused alongside nonsense: an expense with no amount is not a
    // record of anything, and it would silently pad the category totals with
    // rows that mean nothing on a Schedule C.
    if (value == null || !value.isFinite || value <= 0 || value > 1000000) {
      setState(() {
        _amountError =
            'Enter an amount between ${widget.units.currency.symbol}0 and '
            '${widget.units.currency.symbol}1,000,000';
      });
      return;
    }

    final existing = widget.initial;
    Navigator.of(context).pop(
      existing == null
          ? Expense(
              // Client-minted, the way shift ids are, so sync stays a plain
              // upsert with no round trip to allocate a key.
              id: 'expense-${DateTime.now().microsecondsSinceEpoch}',
              amount: value,
              category: _category,
              incurredOn: _incurredOn,
              note: _note.text.trim(),
            )
          : existing.copyWith(
              amount: value,
              category: _category,
              incurredOn: _incurredOn,
              note: _note.text.trim(),
            ),
    );
  }

  Future<void> _pickCategory() async {
    final picked = await showChoiceSheet<ExpenseCategory>(
      context: context,
      title: 'Category',
      current: _category,
      values: ExpenseCategory.values,
      label: (category) => category.label,
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  Future<void> _pickDate() async {
    final now = (widget.today ?? DateTime.now)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _incurredOn,
      // A tax year at a time is what this feeds, so a few years back is the
      // useful range. Future dates are refused: a cost not yet incurred is not
      // deductible, and a mistyped year is the likeliest way to get one.
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _incurredOn = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EditorSheet(
      title: widget.initial == null ? 'Add expense' : 'Edit expense',
      doneLabel: 'Save',
      onDone: _submit,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('expense-amount-field'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '${widget.units.currency.symbol} ',
              errorText: _amountError,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Space.md),
          _PickerRow(
            key: const ValueKey('expense-category-field'),
            icon: Icons.sell_outlined,
            label: 'Category',
            value: _category.label,
            // The Schedule C line is the whole point of categorising, so it is
            // shown at the moment of choosing rather than only in the summary.
            detail: _category.scheduleCLine,
            onTap: _pickCategory,
          ),
          const SizedBox(height: Space.sm),
          _PickerRow(
            key: const ValueKey('expense-date-field'),
            icon: Icons.event_outlined,
            label: 'Date',
            value: _formatDate(_incurredOn),
            onTap: _pickDate,
          ),
          const SizedBox(height: Space.md),
          TextField(
            key: const ValueKey('expense-note-field'),
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'What was it for?',
            ),
          ),
          if (_category.isVehicleCost) ...[
            const SizedBox(height: Space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.directions_car_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'A vehicle cost. It counts only if actual expenses beat the '
                    'standard mileage rate for the year.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime day) {
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
    return '${months[day.month - 1]} ${day.day}, ${day.year}';
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: .4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: Space.md),
              // Intrinsic, not Expanded: the label is one short word and the
              // value is a category name, so the width belongs to the value.
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.end,
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.end,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
