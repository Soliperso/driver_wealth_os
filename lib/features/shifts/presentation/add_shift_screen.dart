import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format/money.dart';
import '../../../core/persistence/app_store.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/domain/work_platform.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../domain/shift.dart';
import 'shift_result_screen.dart';

class AddShiftScreen extends StatefulWidget {
  const AddShiftScreen({
    super.key,
    required this.onSave,
    this.initialShift,
    this.defaultVehicleCostPerMile = AppSnapshot.defaultVehicleCostPerMile,
    this.isNewFromSession = false,
  });

  final ValueChanged<Shift> onSave;
  final Shift? initialShift;

  /// The shift came from a just-finished driving session: hours and miles were
  /// measured, so the screen frames itself as "enter your earnings" rather
  /// than "edit a saved shift".
  final bool isNewFromSession;

  /// Seeds the rate field for a new shift. Editing an existing shift uses that
  /// shift's own rate instead, so a past shift never silently recalculates.
  final double defaultVehicleCostPerMile;

  @override
  State<AddShiftScreen> createState() => _AddShiftScreenState();
}

class _AddShiftScreenState extends State<AddShiftScreen> {
  /// Well above any real shift, but low enough that totals stay finite and the
  /// figures on screen stay readable.
  static const _maxFieldValue = 1000000.0;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hours;
  late final TextEditingController _miles;
  late final TextEditingController _expenses;
  late final TextEditingController _vehicleRate;
  late DateTime _completedAt;
  String? _completedAtError;

  /// One money field per app the shift ran, in the order they were added.
  ///
  /// A tracked shift arrives with a line per app the session had live, all at
  /// zero. Collapsing them into one field would throw away everything the
  /// driver just told the app by switching Lyft on mid-shift.
  final _lines = <_EarningsLine>[];

  /// A session-sourced shift is new, not an edit, even though it arrives with
  /// an initial shift attached.
  bool get _editing => widget.initialShift != null && !widget.isNewFromSession;

  @override
  void initState() {
    super.initState();
    final shift = widget.initialShift;
    for (final line
        in shift?.earnings.entries ??
            const <MapEntry<WorkPlatform, double>>[]) {
      _lines.add(
        _EarningsLine(
          platform: line.key,
          initialGross: _initialNumber(line.value),
        ),
      );
    }
    if (_lines.isEmpty) {
      _lines.add(_EarningsLine(platform: WorkPlatform.uber, initialGross: ''));
    }
    _completedAt = shift?.completedAt ?? DateTime.now();
    _hours = TextEditingController(text: _initialNumber(shift?.hours));
    _miles = TextEditingController(text: _initialNumber(shift?.miles));
    _expenses = TextEditingController(
      text: _initialNumber(shift?.directExpenses, fallback: '0'),
    );
    _vehicleRate = TextEditingController(
      text: _initialNumber(
        shift?.vehicleCostPerMile ?? widget.defaultVehicleCostPerMile,
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _hours,
      _miles,
      _expenses,
      _vehicleRate,
      for (final line in _lines) line.gross,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SoftScaffold(
    title: widget.isNewFromSession
        ? 'Shift complete'
        : _editing
        ? 'Edit shift'
        : 'Add completed shift',
    body: PageFrame(
      maxWidth: 680,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isNewFromSession
                  ? 'How much did you earn?'
                  : _editing
                  ? 'Update the shift details.'
                  : 'Turn earnings into a true-profit picture.',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isNewFromSession
                  ? 'Your time and mileage were tracked. Add what the platform paid and any costs.'
                  : _editing
                  ? 'Your profit will be recalculated before the changes are saved.'
                  : 'Enter the totals from one finished shift. We’ll handle the math.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.isNewFromSession) ...[
              const SizedBox(height: 20),
              _TrackedSummary(shift: widget.initialShift!),
            ],
            const SizedBox(height: 26),
            GlassSurface(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final dateField = _PickerField(
                          key: const ValueKey('shift-date-field'),
                          label: 'Date driven',
                          value: _formatDate(_completedAt),
                          icon: Icons.event_outlined,
                          onTap: _pickDate,
                        );
                        final timeField = _PickerField(
                          key: const ValueKey('shift-time-field'),
                          label: 'Finished at',
                          value: _formatTime(_completedAt),
                          icon: Icons.schedule_outlined,
                          onTap: _pickTime,
                        );
                        if (constraints.maxWidth < 430) {
                          return Column(
                            children: [
                              dateField,
                              const SizedBox(height: 14),
                              timeField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: dateField),
                            const SizedBox(width: 12),
                            Expanded(child: timeField),
                          ],
                        );
                      },
                    ),
                    if (_completedAtError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _completedAtError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'When you drove decides which day-and-time pattern this shift grades.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    ..._earningsFields(),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stackFields = constraints.maxWidth < 430;
                        final hoursField = _numberField(
                          _hours,
                          'Hours online',
                          Icons.schedule_rounded,
                          mustBePositive: true,
                        );
                        final milesField = _numberField(
                          _miles,
                          'Miles driven',
                          Icons.route_rounded,
                        );
                        if (stackFields) {
                          return Column(
                            children: [
                              hoursField,
                              const SizedBox(height: 14),
                              milesField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: hoursField),
                            const SizedBox(width: 12),
                            Expanded(child: milesField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _numberField(
                      _expenses,
                      'Fuel, tolls & parking',
                      Icons.receipt_long_outlined,
                    ),
                    const SizedBox(height: 14),
                    _numberField(
                      _vehicleRate,
                      'Vehicle wear per mile',
                      Icons.directions_car_outlined,
                      helperText:
                          'Maintenance, tires and depreciation only. Fuel is entered above.',
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _calculate,
                      child: Text(
                        _editing
                            ? 'Review updated profit'
                            : 'Calculate true profit',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  );

  /// A platform picker and a money field per app, plus the controls to add and
  /// remove apps.
  ///
  /// On a single-app shift this is the platform dropdown and gross field the
  /// screen has always had, with one extra button underneath. The cost fields
  /// stay outside it: fuel, tolls and vehicle wear were spent once by one car,
  /// and offering to split them per app would invite a number nobody can know.
  List<Widget> _earningsFields() {
    final taken = {for (final line in _lines) line.platform};
    return [
      for (final (index, line) in _lines.indexed) ...[
        if (index > 0) const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<WorkPlatform>(
                key: ValueKey('platform-field-$index'),
                initialValue: line.platform,
                decoration: InputDecoration(
                  labelText: _lines.length > 1
                      ? 'App ${index + 1}'
                      : 'Platform',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: PlatformLogo(platform: line.platform, size: 24),
                  ),
                ),
                // Apps already on another line are left out, so the same app
                // cannot be entered twice. Two lines sharing a platform would
                // silently collapse into one and lose a whole app's earnings.
                items: [
                  for (final platform in WorkPlatform.values)
                    if (platform == line.platform || !taken.contains(platform))
                      DropdownMenuItem(
                        value: platform,
                        child: Row(
                          children: [
                            PlatformLogo(platform: platform, size: 30),
                            const SizedBox(width: 10),
                            Text(platform.displayName),
                          ],
                        ),
                      ),
                ],
                selectedItemBuilder: (context) => [
                  for (final platform in WorkPlatform.values)
                    if (platform == line.platform || !taken.contains(platform))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(platform.displayName),
                      ),
                ],
                onChanged: (value) => setState(() => line.platform = value!),
              ),
            ),
            if (_lines.length > 1) ...[
              const SizedBox(width: 8),
              IconButton(
                key: ValueKey('remove-platform-$index'),
                tooltip: 'Remove ${line.platform.displayName}',
                onPressed: () => _removeLine(index),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _numberField(
          line.gross,
          _lines.length > 1
              ? '${line.platform.displayName} earnings'
              : 'Gross earnings',
          Icons.attach_money_rounded,
          key: ValueKey('gross-field-$index'),
        ),
      ],
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('add-earnings-line'),
          // Nothing left to add once every app is on a line.
          onPressed: _lines.length >= WorkPlatform.values.length
              ? null
              : _addLine,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add another app'),
        ),
      ),
      // The total only earns its space once the figure is not simply the one
      // number already on screen above it.
      if (_lines.length > 1) ...[
        const SizedBox(height: 4),
        Text(
          'Total gross ${Money.cents(_enteredGross())} across '
          '${_lines.length} apps. Your hours, miles and costs below are '
          'counted once for the whole shift.',
          key: const ValueKey('earnings-total'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }

  /// What the money fields currently add up to, ignoring anything unparseable —
  /// this only feeds a helper line, and the validator is what refuses a bad
  /// figure at save time.
  double _enteredGross() => _lines.fold(
    0.0,
    (total, line) => total + (double.tryParse(line.gross.text) ?? 0),
  );

  void _addLine() {
    final taken = {for (final line in _lines) line.platform};
    final next = WorkPlatform.values.firstWhere(
      (platform) => !taken.contains(platform),
      orElse: () => WorkPlatform.other,
    );
    setState(() => _lines.add(_EarningsLine(platform: next, initialGross: '')));
  }

  void _removeLine(int index) {
    final removed = _lines[index];
    setState(() => _lines.removeAt(index));
    // Disposed only after the rebuild that unmounts its field. Disposing a
    // controller a live TextFormField still points at throws.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => removed.gross.dispose(),
    );
  }

  TextFormField _numberField(
    TextEditingController controller,
    String label,
    IconData icon, {
    Key? key,
    String? helperText,
    bool mustBePositive = false,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        helperText: helperText,
        helperMaxLines: 2,
      ),
      validator: (value) {
        final parsed = double.tryParse(value ?? '');
        // double.tryParse accepts 'Infinity' and 'NaN'. Shift.fromJson rejects
        // non-finite numbers, so persisting one would silently drop the shift
        // from history on the next load.
        if (parsed == null || !parsed.isFinite || parsed < 0) {
          return 'Enter a valid number';
        }
        if (parsed > _maxFieldValue) {
          return 'Enter a number below ${_maxFieldValue.toStringAsFixed(0)}';
        }
        if (mustBePositive && parsed == 0) {
          return 'Enter a number above 0';
        }
        return null;
      },
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _completedAt.isAfter(now) ? now : _completedAt,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      helpText: 'Date driven',
    );
    if (picked == null) return;
    setState(() {
      _completedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _completedAt.hour,
        _completedAt.minute,
      );
      _completedAtError = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_completedAt),
      helpText: 'Time the shift finished',
    );
    if (picked == null) return;
    setState(() {
      _completedAt = DateTime(
        _completedAt.year,
        _completedAt.month,
        _completedAt.day,
        picked.hour,
        picked.minute,
      );
      _completedAtError = null;
    });
  }

  void _calculate() {
    final formValid = _formKey.currentState!.validate();
    // The date picker cannot reach the future, but picking a later time on
    // today's date can, so the combined value is what has to be checked.
    final inFuture = _completedAt.isAfter(DateTime.now());
    setState(
      () => _completedAtError = inFuture
          ? 'This shift finishes in the future. Pick a time that has already passed.'
          : null,
    );
    if (!formValid || inFuture) return;
    final shift = Shift(
      id:
          widget.initialShift?.id ??
          'manual-${DateTime.now().microsecondsSinceEpoch}',
      // Safe as a map even with several lines: the dropdowns cannot offer an
      // app another line already holds, so no key can be overwritten here.
      earnings: {
        for (final line in _lines) line.platform: double.parse(line.gross.text),
      },
      hours: double.parse(_hours.text),
      miles: double.parse(_miles.text),
      directExpenses: double.parse(_expenses.text),
      vehicleCostPerMile: double.parse(_vehicleRate.text),
      completedAt: _completedAt,
      source: widget.initialShift?.source ?? ShiftSource.manual,
      // Reaching Calculate means the driver has seen and confirmed the cost
      // field. Zero is a valid reviewed answer.
      costsReviewed: true,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ShiftResultScreen(
          shift: shift,
          saveLabel: _editing ? 'Save changes' : 'Save to Today',
          onSave: () => widget.onSave(shift),
        ),
      ),
    );
  }

  static String _initialNumber(double? value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  }

  static String _formatDate(DateTime date) {
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
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final label = '${months[date.month - 1]} ${date.day}, ${date.year}';
    return isToday ? 'Today · $label' : label;
  }

  static String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// What the session measured, shown before the driver is asked for money.
///
/// The figures remain editable in the form below — GPS can be interrupted, and
/// a driver who knows the tracking missed a stretch must be able to correct it
/// rather than accept a number the app insists on.
/// One app's money field on the entry form.
///
/// Mutable [platform] rather than a rebuilt record, so changing the dropdown
/// does not drop the text the driver has already typed into that row.
class _EarningsLine {
  _EarningsLine({required this.platform, required String initialGross})
    : gross = TextEditingController(text: initialGross);

  WorkPlatform platform;
  final TextEditingController gross;
}

class _TrackedSummary extends StatelessWidget {
  const _TrackedSummary({required this.shift});

  final Shift shift;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      key: const ValueKey('tracked-session-summary'),
      padding: const EdgeInsets.all(20),
      tint: colors.primaryContainer.withValues(alpha: .82),
      child: Row(
        children: [
          Expanded(
            child: _TrackedMetric(
              label: 'Tracked time',
              value: Money.hours(shift.hours),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: colors.outlineVariant.withValues(alpha: .5),
          ),
          Expanded(
            child: _TrackedMetric(
              label: 'Tracked miles',
              value: Money.number(shift.miles),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackedMetric extends StatelessWidget {
  const _TrackedMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

/// A read-only field that opens a picker. Deliberately not a [TextFormField]:
/// the value is never typed, and keeping it out of the form's text fields
/// leaves positional field lookups in the widget tests meaningful.
class _PickerField extends StatelessWidget {
  const _PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label, $value',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    ),
  );
}
