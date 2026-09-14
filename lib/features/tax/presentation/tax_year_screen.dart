import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/editor_sheets.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/metric_panel.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/section_heading.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../settings/application/history_export.dart';
import '../../settings/domain/measurement_units.dart';
import '../../shifts/domain/shift.dart';
import '../application/receipt_store.dart';
import '../domain/expense.dart';
import '../domain/quarterly_estimate.dart';
import '../domain/tax_year_summary.dart';
import 'expense_editor_sheet.dart';

/// A driver's year, arranged the way a tax return asks for it.
///
/// The app has been measuring miles and collecting costs all along, so it
/// already holds both halves of the one comparison that decides a gig driver's
/// vehicle deduction: the standard mileage rate against actual expenses. Almost
/// nobody knows the two are alternatives, let alone which way round it falls for
/// their car. That comparison is what this screen exists to show.
///
/// Nothing here is tax advice and nothing here is filed. It is arithmetic over
/// the driver's own records, framed as "set aside" rather than "you owe",
/// because the real figure depends on filing status, other income and the QBI
/// deduction — none of which the app knows.
class TaxYearScreen extends StatefulWidget {
  const TaxYearScreen({
    super.key,
    required this.shifts,
    required this.expenses,
    required this.onExpenseAdded,
    required this.onExpenseUpdated,
    required this.onExpenseDeleted,
    this.units = const MeasurementUnits(),
    this.clock,
    this.receipts,
  });

  /// Injectable so a test can attach a receipt without a camera.
  final ReceiptStore? receipts;

  final List<Shift> shifts;
  final List<Expense> expenses;
  final MeasurementUnits units;
  final ValueChanged<Expense> onExpenseAdded;
  final ValueChanged<Expense> onExpenseUpdated;
  final ValueChanged<String> onExpenseDeleted;

  /// Injectable wall clock. This screen anchors on the current tax year, so a
  /// test with fixed fixture dates could otherwise only pass during the year it
  /// was written.
  final DateTime Function()? clock;

  @override
  State<TaxYearScreen> createState() => _TaxYearScreenState();
}

class _TaxYearScreenState extends State<TaxYearScreen> {
  late DateTime _now;
  late int _year;
  late List<int> _years;
  late TaxYearSummary _summary;

  @override
  void initState() {
    super.initState();
    _now = (widget.clock ?? DateTime.now)();
    _year = _now.year;
    _recompute();
  }

  @override
  void didUpdateWidget(TaxYearScreen old) {
    super.didUpdateWidget(old);
    // The lists are mutated in place upstream, so neither identity nor length
    // reliably signals an edit. A parent rebuild is the signal.
    _recompute();
  }

  /// Every figure on this screen is a full scan of both record lists, so it is
  /// computed once per data change and held — never inside [build].
  void _recompute() {
    _years = TaxYearSummary.yearsCovered(
      shifts: widget.shifts,
      expenses: widget.expenses,
    );
    // A driver with no records at all still gets the current year rather than
    // an empty picker with nothing selected.
    if (_years.isEmpty) _years = [_now.year];
    if (!_years.contains(_year)) _year = _years.first;
    _summary = TaxYearSummary.from(
      year: _year,
      shifts: widget.shifts,
      expenses: widget.expenses,
    );
  }

  List<Expense> get _yearExpenses =>
      widget.expenses.where((expense) => expense.occurredIn(_year)).toList()
        ..sort((a, b) => b.incurredOn.compareTo(a.incurredOn));

  Future<void> _chooseYear() async {
    final picked = await showChoiceSheet<int>(
      context: context,
      title: 'Tax year',
      current: _year,
      values: _years,
      label: (year) => '$year',
    );
    if (picked == null || !mounted || picked == _year) return;
    setState(() {
      _year = picked;
      _recompute();
    });
  }

  Future<void> _addExpense([ExpenseCategory? category]) async {
    final expense = await ExpenseEditorSheet.show(
      context,
      units: widget.units,
      initialCategory: category,
      today: widget.clock,
      receipts: widget.receipts,
    );
    if (expense != null) widget.onExpenseAdded(expense);
  }

  Future<void> _editExpense(Expense expense) async {
    final edited = await ExpenseEditorSheet.show(
      context,
      units: widget.units,
      initial: expense,
      today: widget.clock,
      receipts: widget.receipts,
    );
    if (edited != null) widget.onExpenseUpdated(edited);
  }

  /// The selected year only — a filing covers one year and nothing else.
  ///
  /// Settings exports the whole history from the same builder; the year is the
  /// only difference, so the two can never drift into different file formats.
  Future<void> _exportYear() async {
    final exported = await HistoryExport(
      units: widget.units,
    ).share(widget.shifts, expenses: widget.expenses, year: _year);
    if (!mounted || exported) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('No records in $_year to export.')));
  }

  Future<void> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text(
          '${widget.units.cents(expense.amount)} · ${expense.category.label}. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onExpenseDeleted(expense.id);
  }

  @override
  Widget build(BuildContext context) {
    final units = widget.units;
    final summary = _summary;
    final expenses = _yearExpenses;
    final hasRecords = summary.shiftCount > 0 || expenses.isNotEmpty;

    return SoftScaffold(
      title: 'Taxes',
      actions: [
        TextButton(
          key: const ValueKey('tax-year-picker'),
          onPressed: _years.length > 1 ? _chooseYear : null,
          child: Text('$_year'),
        ),
        // The primary action of this screen, so it stays reachable rather than
        // living below the fold beside the list it appends to.
        IconButton(
          key: const ValueKey('tax-add-expense'),
          onPressed: _addExpense,
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add expense',
        ),
        IconButton(
          key: const ValueKey('tax-export-year'),
          onPressed: hasRecords ? _exportYear : null,
          icon: const Icon(Icons.ios_share_rounded),
          tooltip: 'Export $_year',
        ),
      ],
      body: PageFrame(
        maxWidth: 680,
        // The empty card claims the height it is given, so it is the body
        // rather than a row inside a scroll view with no bound to claim.
        child: !hasRecords
            ? EmptyStateCard(
                icon: Icons.receipt_long_rounded,
                title: 'Nothing to total yet',
                message:
                    'Log a session or add an expense and this year assembles '
                    'itself — including which vehicle deduction is worth more.',
                action: OutlinedButton.icon(
                  key: const ValueKey('tax-empty-add-expense'),
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add expense'),
                ),
              )
            : ListView(
                children: [
                  _MethodComparison(summary: summary, units: units),
                  const SizedBox(height: Space.lg),
                  MetricPanel(
                    rows: [
                      [
                        (
                          label: 'Gross',
                          value: units.whole(summary.gross),
                          loss: false,
                        ),
                        (
                          label: 'Deductions',
                          value: units.whole(summary.totalDeductions),
                          loss: false,
                        ),
                      ],
                      [
                        (
                          label: 'Net before tax',
                          value: units.whole(summary.netBeforeTax),
                          loss: summary.netBeforeTax < 0,
                        ),
                        (
                          label: 'Deductible miles',
                          value: units.distanceLabel(summary.deductibleMiles),
                          loss: false,
                        ),
                      ],
                    ],
                  ),
                  if (summary.isProvisional) ...[
                    const SizedBox(height: Space.md),
                    _Notice(
                      key: const ValueKey('tax-provisional-notice'),
                      icon: Icons.pending_outlined,
                      message:
                          '${units.distanceLabel(summary.unratedMiles)} of driving '
                          'falls in a period the IRS has not published a rate for, '
                          'so the standard-mileage figure is not final.',
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  _SetAsideCard(summary: summary, units: units, now: _now),
                  const SizedBox(height: Space.xl),
                  const SectionHeading(title: 'Expenses'),
                  const SizedBox(height: Space.sm),
                  if (expenses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.md),
                      child: Text(
                        'No standalone expenses recorded for $_year. Fuel, tolls and '
                        'parking entered on a session are already counted.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final expense in expenses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: _ExpenseRow(
                          expense: expense,
                          units: units,
                          onTap: () => _editExpense(expense),
                          onDelete: () => _confirmDelete(expense),
                        ),
                      ),
                  const SizedBox(height: Space.bottomNavClearance),
                ],
              ),
      ),
    );
  }
}

/// The one comparison the screen exists for: mileage rate against real costs.
class _MethodComparison extends StatelessWidget {
  const _MethodComparison({required this.summary, required this.units});

  final TaxYearSummary summary;
  final MeasurementUnits units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final standardWins =
        summary.betterMethod == DeductionMethod.standardMileage;
    // The part of the actual-expenses figure that is modelled rather than
    // recorded: miles × the driver's per-mile rate.
    final modelledWear = summary.shiftSummary.vehicleCost;
    return GlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vehicle deduction',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            units.whole(summary.betterVehicleDeduction),
            key: const ValueKey('tax-better-deduction'),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            standardWins
                ? 'Standard mileage is worth more this year'
                : 'Your actual expenses are worth more this year',
            key: const ValueKey('tax-better-method'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.lg),
          _MethodRow(
            label: 'Standard mileage',
            detail: units.distanceLabel(summary.deductibleMiles),
            value: units.whole(summary.standardMileageDeduction),
            selected: standardWins,
          ),
          const SizedBox(height: Space.sm),
          _MethodRow(
            label: 'Actual expenses',
            detail: 'Fuel, upkeep, estimated wear',
            value: units.whole(summary.vehicleExpenses),
            selected: !standardWins,
          ),
          // The wear allowance is miles × the rate set in Settings, not a cost
          // anyone receipted. It is honest as a running estimate of what the
          // car costs, but it is sitting on the side of a comparison the IRS
          // expects to be backed by records, so it cannot go unlabelled — least
          // of all when it is the side the screen is recommending.
          if (modelledWear > 0) ...[
            const SizedBox(height: Space.sm),
            Text(
              'Includes ${units.cents(modelledWear)} of estimated vehicle wear '
              'at your Settings rate, not receipted cost. Claiming actual '
              'expenses means backing them with your own records.',
              key: const ValueKey('tax-actual-estimate-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (summary.methodAdvantage > 0) ...[
            const SizedBox(height: Space.md),
            Text(
              'Choosing the better one is worth '
              '${units.cents(summary.methodAdvantage)} more. You cannot claim '
              'both — the mileage rate already covers running the car.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (summary.otherExpenses > 0) ...[
            const SizedBox(height: Space.md),
            Text(
              'Plus ${units.cents(summary.otherExpenses)} of non-vehicle costs, '
              'claimable either way.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.selected,
  });

  final String label;
  final String detail;
  final String value;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: selected
            ? colors.primary.withValues(alpha: .10)
            : colors.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(12),
        border: selected
            ? Border.all(color: colors.primary.withValues(alpha: .45))
            : null,
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: selected ? colors.primary : colors.outlineVariant,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? colors.primary : colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SetAsideCard extends StatelessWidget {
  const _SetAsideCard({
    required this.summary,
    required this.units,
    required this.now,
  });

  final TaxYearSummary summary;
  final MeasurementUnits units;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final setAside = SetAside.of(summary.netBeforeTax);
    final next = TaxQuarters.nextDue(now, year: summary.year);
    return GlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set aside',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            units.whole(setAside.amount),
            key: const ValueKey('tax-set-aside'),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${(setAside.rate * 100).round()}% of net, a common starting point '
            'for self-employment. Nothing is withheld from gig work, so this is '
            'money to hold back — not a bill.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (next != null) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    '${next.label} estimated payment is due '
                    '${_formatDue(next.dueDate)}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
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

  static String _formatDue(DateTime day) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[day.month - 1]} ${day.day}, ${day.year}';
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.units,
    required this.onTap,
    required this.onDelete,
  });

  final Expense expense;
  final MeasurementUnits units;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.category.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      expense.note.isEmpty
                          ? _formatDay(expense.incurredOn)
                          : '${_formatDay(expense.incurredOn)} · ${expense.note}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                units.cents(expense.amount),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              // A quiet marker, not the photo: the list is scanned for amounts,
              // and a row of thumbnails would compete with them.
              if (expense.receiptPath != null) ...[
                const SizedBox(width: Space.sm),
                Icon(
                  Icons.attach_file_rounded,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
              ],
              if (expense.category.isVehicleCost) ...[
                const SizedBox(width: Space.sm),
                Icon(
                  Icons.directions_car_rounded,
                  size: 16,
                  color: colors.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDay(DateTime day) {
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
    return '${months[day.month - 1]} ${day.day}';
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
