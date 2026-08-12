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
  late final TextEditingController _gross;
  late final TextEditingController _hours;
  late final TextEditingController _miles;
  late final TextEditingController _expenses;
  late final TextEditingController _vehicleRate;
  late WorkPlatform _platform;
  late DateTime _completedAt;
  String? _completedAtError;

  /// A session-sourced shift is new, not an edit, even though it arrives with
  /// an initial shift attached.
  bool get _editing => widget.initialShift != null && !widget.isNewFromSession;

  @override
  void initState() {
    super.initState();
    final shift = widget.initialShift;
    _platform = shift?.platform ?? WorkPlatform.uber;
    _completedAt = shift?.completedAt ?? DateTime.now();
    _gross = TextEditingController(text: _initialNumber(shift?.gross));
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
      _gross,
      _hours,
      _miles,
      _expenses,
      _vehicleRate,
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
                    DropdownButtonFormField<WorkPlatform>(
                      initialValue: _platform,
                      decoration: InputDecoration(
                        labelText: 'Platform',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: PlatformLogo(platform: _platform, size: 24),
                        ),
                      ),
                      items: WorkPlatform.values
                          .map(
                            (platform) => DropdownMenuItem(
                              value: platform,
                              child: Row(
                                children: [
                                  PlatformLogo(platform: platform, size: 30),
                                  const SizedBox(width: 10),
                                  Text(platform.displayName),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      selectedItemBuilder: (context) => WorkPlatform.values
                          .map(
                            (platform) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(platform.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _platform = value!),
                    ),
                    const SizedBox(height: 14),
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
                    _numberField(
                      _gross,
                      'Gross earnings',
                      Icons.attach_money_rounded,
                    ),
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

  TextFormField _numberField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? helperText,
    bool mustBePositive = false,
  }) {
    return TextFormField(
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
      platform: _platform,
      gross: double.parse(_gross.text),
      hours: double.parse(_hours.text),
      miles: double.parse(_miles.text),
      directExpenses: double.parse(_expenses.text),
      vehicleCostPerMile: double.parse(_vehicleRate.text),
      completedAt: _completedAt,
      source: widget.initialShift?.source ?? ShiftSource.manual,
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
              value: _hoursLabel(shift.hours),
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

  static String _hoursLabel(double hours) {
    final whole = hours.floor();
    final minutes = ((hours - whole) * 60).round();
    return '${whole}h ${minutes.toString().padLeft(2, '0')}m';
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
