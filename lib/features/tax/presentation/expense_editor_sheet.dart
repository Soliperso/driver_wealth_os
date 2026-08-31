import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/editor_sheets.dart';
import '../../settings/domain/measurement_units.dart';
import '../application/receipt_store.dart';
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
    this.receipts,
  });

  /// The expense being edited, or null when adding a new one.
  final Expense? initial;

  /// Injectable so a widget test can exercise the capture path without a
  /// camera. Null falls back to the real device store.
  final ReceiptStore? receipts;

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
    ReceiptStore? receipts,
  }) => showModalBottomSheet<Expense>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ExpenseEditorSheet(
      units: units,
      initial: initial,
      initialCategory: initialCategory,
      today: today,
      receipts: receipts,
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
  late ReceiptStore _receipts;
  String? _amountError;

  /// The photo as it stands in this sheet, which is not yet what the record
  /// holds — the driver can still back out.
  String? _receiptPath;

  /// Photos written during this edit. Whichever the driver does not keep is
  /// deleted on the way out, so a few false starts at the camera do not leave
  /// orphaned images on the device forever.
  final _written = <String>[];

  @override
  void initState() {
    super.initState();
    _receipts = widget.receipts ?? DeviceReceiptStore();
    final initial = widget.initial;
    _receiptPath = initial?.receiptPath;
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

    // Every photo taken here except the one being kept.
    for (final path in _written.where((path) => path != _receiptPath)) {
      unawaited(_receipts.discard(path));
    }
    // A receipt the driver removed while editing goes too, but only once the
    // edit is actually saved — backing out must leave the record untouched.
    final replaced = widget.initial?.receiptPath;
    if (replaced != null && replaced != _receiptPath) {
      unawaited(_receipts.discard(replaced));
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
              receiptPath: _receiptPath,
            )
          : existing.copyWith(
              amount: value,
              category: _category,
              incurredOn: _incurredOn,
              note: _note.text.trim(),
              receiptPath: _receiptPath,
              clearReceipt: _receiptPath == null,
            ),
    );
  }

  Future<void> _addReceipt() async {
    final source = await showModalBottomSheet<ReceiptSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('receipt-source-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ReceiptSource.camera),
            ),
            ListTile(
              key: const ValueKey('receipt-source-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(context).pop(ReceiptSource.gallery),
            ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    String? path;
    try {
      path = await _receipts.capture(source);
    } catch (_) {
      // A refused permission or a cancelled camera is not an error the driver
      // needs explained twice — the OS has already said its piece.
      path = null;
    }
    if (path == null || !mounted) return;
    setState(() {
      _written.add(path!);
      _receiptPath = path;
    });
  }

  void _removeReceipt() {
    // Not deleted from disk here. Until the edit is saved the driver can still
    // back out, and a discarded file cannot be brought back.
    setState(() => _receiptPath = null);
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
          const SizedBox(height: Space.md),
          _ReceiptField(
            path: _receiptPath,
            onAdd: _addReceipt,
            onRemove: _removeReceipt,
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

/// The receipt slot: a button when there is no photo, a thumbnail when there is.
///
/// The line about the image staying on the device is not decoration. A driver
/// being asked to photograph something with their card number on it is owed the
/// reason it is safe, at the moment they are deciding.
class _ReceiptField extends StatelessWidget {
  const _ReceiptField({
    required this.path,
    required this.onAdd,
    required this.onRemove,
  });

  final String? path;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final stored = path;

    if (stored == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('expense-add-receipt'),
          onPressed: onAdd,
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: const Text('Attach receipt'),
        ),
      );
    }

    return Container(
      key: const ValueKey('expense-receipt-thumbnail'),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _Thumbnail(path: stored),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              // Checked up front rather than left to Image.file's error path,
              // which resolves a frame or more later and leaves an empty slot
              // in the meantime.
              File(stored).existsSync()
                  ? 'Receipt attached. The photo stays on this device.'
                  : 'The photo for this receipt is no longer on this device.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('expense-remove-receipt'),
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Remove receipt',
          ),
        ],
      ),
    );
  }
}

/// The receipt photo, or a marker saying it is gone.
///
/// Existence is tested synchronously so the missing case paints on the first
/// frame. `Image.file` reports a missing file through `errorBuilder`, but only
/// after the read fails, which leaves a blank square in the meantime — and a
/// blank square in a form reads as a layout bug rather than as a lost photo.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  static const _size = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final missing = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 20,
        color: colors.onSurfaceVariant,
      ),
    );

    if (!File(path).existsSync()) return missing;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        // Still a backstop: the file can be unreadable rather than absent.
        errorBuilder: (_, _, _) => missing,
      ),
    );
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
