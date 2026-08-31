import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/editor_sheets.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/section_heading.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../shifts/domain/shift.dart';
import '../../tax/domain/expense.dart';
import '../../tax/domain/tax_year_summary.dart';
import '../domain/driving_costs.dart';
import '../domain/measurement_units.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.driverName,
    required this.shifts,
    required this.expenses,
    required this.onOpenTaxes,
    required this.dailyGoal,
    required this.drivingCosts,
    required this.hourlyFloor,
    required this.weekStartsOn,
    required this.drivingDaysPerWeek,
    required this.units,
    required this.onDriverNameChanged,
    required this.onDailyGoalChanged,
    required this.onVehicleCostPerMileChanged,
    required this.onEnergySourceChanged,
    required this.onFuelEfficiencyChanged,
    required this.onFuelPriceChanged,
    required this.onHourlyFloorChanged,
    required this.onWeekStartsOnChanged,
    required this.onDrivingDaysPerWeekChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onExportData,
    required this.onOpenPrivacy,
    this.accountEmail,
    this.onSignOut,
    this.onConnectAccounts,
    this.onOpenAdmin,
  });

  final String driverName;

  /// Both record lists, so the expense-categories sheet can show what the
  /// driver actually spent rather than a list of enum constants.
  final List<Shift> shifts;
  final List<Expense> expenses;

  /// Opens the Taxes tab, where an expense is actually managed. The sheet here
  /// explains the categories; it is not a second place to edit records.
  final VoidCallback onOpenTaxes;
  final double dailyGoal;
  final DrivingCosts drivingCosts;
  final double hourlyFloor;
  final int weekStartsOn;
  final int drivingDaysPerWeek;
  final MeasurementUnits units;
  final ValueChanged<String> onDriverNameChanged;
  final ValueChanged<double> onDailyGoalChanged;
  final ValueChanged<double> onVehicleCostPerMileChanged;
  final ValueChanged<EnergySource> onEnergySourceChanged;
  final ValueChanged<double> onFuelEfficiencyChanged;
  final ValueChanged<double> onFuelPriceChanged;
  final ValueChanged<double> onHourlyFloorChanged;
  final ValueChanged<int> onWeekStartsOnChanged;
  final ValueChanged<int> onDrivingDaysPerWeekChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onExportData;
  final VoidCallback onOpenPrivacy;
  final String? accountEmail;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onConnectAccounts;
  final VoidCallback? onOpenAdmin;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final costs = widget.drivingCosts;
    final units = widget.units;
    return SoftScaffold(
      title: 'Settings',
      body: PageFrame(
        maxWidth: 680,
        child: ListView(
          children: [
            _SettingsSection(
              title: 'Profile',
              children: [
                _SettingsTile(
                  key: const ValueKey('settings-profile'),
                  icon: Icons.person_outline_rounded,
                  title: widget.driverName,
                  onTap: _editName,
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            _SettingsSection(
              title: 'Earnings goals',
              children: [
                _SettingsTile(
                  key: const ValueKey('settings-daily-goal'),
                  icon: Icons.flag_outlined,
                  title: 'Daily profit goal',
                  value: units.whole(widget.dailyGoal),
                  onTap: _editDailyGoal,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-hourly-floor'),
                  icon: Icons.speed_rounded,
                  title: 'Minimum profitable rate',
                  value: '${units.whole(widget.hourlyFloor)}/hr',
                  onTap: _editHourlyFloor,
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            _SettingsSection(
              title: 'Vehicle & costs',
              children: [
                _SettingsTile(
                  key: const ValueKey('settings-energy-source'),
                  icon: Icons.local_gas_station_outlined,
                  title: 'Vehicle',
                  value: costs.energySource.label,
                  onTap: _chooseEnergySource,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-fuel-efficiency'),
                  icon: Icons.energy_savings_leaf_outlined,
                  title: 'Fuel economy',
                  value:
                      '${_plain(costs.fuelEfficiency)} ${_efficiencyUnit(costs.energySource)}',
                  onTap: _editFuelEfficiency,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-fuel-price'),
                  icon: Icons.payments_outlined,
                  title: 'Fuel price',
                  value:
                      '${units.cents(costs.fuelPrice)}/${costs.energySource.unit}',
                  onTap: _editFuelPrice,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-vehicle-rate'),
                  icon: Icons.directions_car_outlined,
                  title: 'Vehicle cost',
                  value: units.rateLabel(costs.vehicleCostPerMile),
                  onTap: _editVehicleRate,
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            _DrivingCostSummary(costs: costs, units: units),
            const SizedBox(height: Space.xl),
            _SettingsSection(
              title: 'Driving',
              children: [
                _SettingsTile(
                  key: const ValueKey('settings-week-start'),
                  icon: Icons.calendar_view_week_outlined,
                  title: 'Week starts',
                  value: widget.weekStartsOn == DateTime.sunday
                      ? 'Sunday'
                      : 'Monday',
                  onTap: _chooseWeekStart,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-weekly-target'),
                  icon: Icons.calendar_month_outlined,
                  title: 'Weekly driving target',
                  value:
                      '${widget.drivingDaysPerWeek} ${widget.drivingDaysPerWeek == 1 ? 'day' : 'days'}',
                  onTap: _chooseDrivingDays,
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            _SettingsSection(
              title: 'App',
              children: [
                _SettingsTile(
                  key: const ValueKey('settings-expense-categories'),
                  icon: Icons.receipt_long_rounded,
                  title: 'Expense categories',
                  subtitle: 'Deductible business expenses',
                  // The year's recorded total, not the number of enum
                  // constants — a count of categories is a fact about the app
                  // rather than about the driver.
                  value: units.whole(_recordedExpenses),
                  onTap: _showExpenseCategories,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-theme-mode'),
                  icon: _themeIcon(widget.themeMode),
                  title: 'Appearance',
                  value: _themeLabel(widget.themeMode),
                  onTap: _chooseThemeMode,
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            _SettingsSection(
              title: 'Data & account',
              children: [
                if (widget.accountEmail != null || widget.onSignOut != null)
                  _SettingsTile(
                    key: const ValueKey('settings-backup-sync'),
                    icon: Icons.cloud_done_outlined,
                    title: 'Backup & sync',
                    subtitle: widget.accountEmail,
                    value: 'On',
                    onTap: _showBackupInfo,
                  ),
                _SettingsTile(
                  key: const ValueKey('settings-export-data'),
                  icon: Icons.ios_share_rounded,
                  title: 'Export driving data',
                  onTap: widget.onExportData,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-privacy-security'),
                  icon: Icons.shield_outlined,
                  title: 'Privacy & security',
                  onTap: widget.onOpenPrivacy,
                ),
                if (widget.onConnectAccounts != null)
                  _SettingsTile(
                    key: const ValueKey('settings-work-accounts'),
                    icon: Icons.link_rounded,
                    title: 'Work accounts',
                    onTap: widget.onConnectAccounts,
                  ),
                if (widget.onOpenAdmin != null)
                  _SettingsTile(
                    key: const ValueKey('settings-open-admin'),
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Admin dashboard',
                    onTap: widget.onOpenAdmin,
                  ),
                if (widget.onSignOut != null)
                  _SettingsTile(
                    key: const ValueKey('settings-sign-out'),
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    onTap: () => widget.onSignOut!(),
                  ),
              ],
            ),
            const SizedBox(height: Space.bottomNavClearance),
          ],
        ),
      ),
    );
  }

  Future<void> _editName() async {
    final value = await _showTextEditor(
      title: 'First name',
      initialValue: widget.driverName,
      fieldKey: const ValueKey('settings-profile-field'),
      textCapitalization: TextCapitalization.words,
      validator: (text) => text.trim().isEmpty ? 'Enter your name' : null,
    );
    if (value != null) widget.onDriverNameChanged(value.trim());
  }

  Future<void> _editDailyGoal() async {
    final value = await _showNumberEditor(
      title: 'Daily profit goal',
      initialValue: widget.dailyGoal,
      fieldKey: const ValueKey('settings-daily-goal-field'),
      prefixText: '${widget.units.currency.symbol} ',
      suffixText: '/ day',
      min: 1,
      max: 100000,
      rangeError:
          'Enter an amount between ${widget.units.currency.symbol}1 and '
          '${widget.units.currency.symbol}100,000',
    );
    if (value != null) widget.onDailyGoalChanged(value);
  }

  Future<void> _editHourlyFloor() async {
    final value = await _showNumberEditor(
      title: 'Minimum profitable rate',
      initialValue: widget.hourlyFloor,
      fieldKey: const ValueKey('settings-hourly-floor-field'),
      prefixText: '${widget.units.currency.symbol} ',
      suffixText: '/ hr',
      min: 1,
      max: 10000,
      rangeError:
          'Enter an amount between ${widget.units.currency.symbol}1 and '
          '${widget.units.currency.symbol}10,000',
    );
    if (value != null) widget.onHourlyFloorChanged(value);
  }

  Future<void> _editFuelEfficiency() async {
    final costs = widget.drivingCosts;
    final value = await _showNumberEditor(
      title: 'Fuel economy',
      initialValue: costs.fuelEfficiency,
      fieldKey: const ValueKey('settings-fuel-efficiency-field'),
      suffixText: _efficiencyUnit(costs.energySource),
      min: .1,
      max: 500,
      rangeError: 'Enter a value between 0.1 and 500',
    );
    if (value != null) widget.onFuelEfficiencyChanged(value);
  }

  Future<void> _editFuelPrice() async {
    final costs = widget.drivingCosts;
    final value = await _showNumberEditor(
      title: 'Fuel price',
      initialValue: costs.fuelPrice,
      fieldKey: const ValueKey('settings-fuel-price-field'),
      prefixText: '${widget.units.currency.symbol} ',
      suffixText: '/ ${costs.energySource.unit}',
      min: 0,
      max: 100,
      rangeError:
          'Enter a price between ${widget.units.currency.symbol}0 and '
          '${widget.units.currency.symbol}100',
    );
    if (value != null) widget.onFuelPriceChanged(value);
  }

  Future<void> _editVehicleRate() async {
    final units = widget.units;
    final symbol = units.currency.symbol;
    final value = await _showNumberEditor(
      title: 'Vehicle cost',
      initialValue: widget.drivingCosts.vehicleCostPerMile,
      fieldKey: const ValueKey('settings-vehicle-rate-field'),
      prefixText: '$symbol ',
      suffixText: '/ ${units.distance.symbol}',
      min: 0,
      max: 100,
      rangeError: 'Enter a rate between ${symbol}0 and ${symbol}100',
    );
    // Typed per mile and stored per mile, so the figure goes straight through.
    if (value != null) widget.onVehicleCostPerMileChanged(value);
  }

  Future<void> _chooseEnergySource() async {
    final selected = await _showChoice<EnergySource>(
      title: 'Vehicle',
      current: widget.drivingCosts.energySource,
      values: EnergySource.values,
      label: (source) => source.label,
    );
    if (selected != null && selected != widget.drivingCosts.energySource) {
      widget.onEnergySourceChanged(selected);
    }
  }

  /// Both themes were fully defined, persisted and synced, and there was no
  /// way to pick one: a driver could only get dark mode by changing their OS
  /// setting. "System" stays the default, so nothing changes for anyone who
  /// never opens this.
  Future<void> _chooseThemeMode() async {
    final selected = await _showChoice<ThemeMode>(
      title: 'Appearance',
      current: widget.themeMode,
      values: ThemeMode.values,
      label: _themeLabel,
    );
    if (selected != null && selected != widget.themeMode) {
      widget.onThemeModeChanged(selected);
    }
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Match device',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  static IconData _themeIcon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };

  Future<void> _chooseWeekStart() async {
    final selected = await _showChoice<int>(
      title: 'Week starts',
      current: widget.weekStartsOn,
      values: const [DateTime.monday, DateTime.sunday],
      label: (day) => day == DateTime.sunday ? 'Sunday' : 'Monday',
    );
    if (selected != null) widget.onWeekStartsOnChanged(selected);
  }

  Future<void> _chooseDrivingDays() async {
    final selected = await _showChoice<int>(
      title: 'Weekly driving target',
      current: widget.drivingDaysPerWeek,
      values: const [1, 2, 3, 4, 5, 6, 7],
      label: (days) => '$days ${days == 1 ? 'day' : 'days'} per week',
    );
    if (selected != null) widget.onDrivingDaysPerWeekChanged(selected);
  }

  /// This year's totals per category, and whether the mileage rate has already
  /// absorbed the vehicle ones.
  TaxYearSummary get _taxYear => TaxYearSummary.from(
    year: DateTime.now().year,
    shifts: widget.shifts,
    expenses: widget.expenses,
  );

  /// Standalone expenses recorded this year. Deliberately not the tax year's
  /// full deduction: this tile is about the records the driver has entered
  /// here, and folding in per-shift fuel would make the number disagree with
  /// the list the sheet then shows.
  double get _recordedExpenses {
    final year = DateTime.now().year;
    var total = 0.0;
    for (final expense in widget.expenses) {
      if (expense.occurredIn(year)) total += expense.amount;
    }
    return total;
  }

  Future<void> _showExpenseCategories() async {
    final units = widget.units;
    final summary = _taxYear;
    final totals = summary.expensesByCategory;
    final standardMileage =
        summary.betterMethod == DeductionMethod.standardMileage;

    // Categories the driver has actually used come first. The rest stay below
    // as the reference list they have always been, so the sheet still answers
    // "what can I even claim?" for someone who has recorded nothing yet.
    final ordered = [
      ...ExpenseCategory.values.where((c) => (totals[c] ?? 0) > 0),
      ...ExpenseCategory.values.where((c) => (totals[c] ?? 0) <= 0),
    ];

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.sm,
            Space.xl,
            Space.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Expense categories',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.sm),
              Text(
                standardMileage
                    ? 'Costs you can deduct on Schedule C, with your '
                          '${summary.year} totals. Standard mileage is ahead '
                          'this year, so the vehicle costs marked below are '
                          'already covered by the rate and cannot be claimed '
                          'on top of it.'
                    : 'Costs you can deduct on Schedule C, with your '
                          '${summary.year} totals. Your actual expenses are '
                          'ahead this year, so the vehicle costs marked below '
                          'are the ones being claimed — the standard mileage '
                          'rate is the alternative, not an addition.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: Space.lg),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: ordered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (context, index) => _ExpenseCategoryCard(
                    category: ordered[index],
                    amount: totals[ordered[index]] ?? 0,
                    units: units,
                    coveredByMileageRate:
                        standardMileage && ordered[index].isVehicleCost,
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              FilledButton.icon(
                key: const ValueKey('settings-open-taxes'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onOpenTaxes();
                },
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Manage expenses'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBackupInfo() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.sm,
            Space.xl,
            Space.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backup & sync is active',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Changes save to this device first, then sync to your account when a connection is available.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.accountEmail != null) ...[
                const SizedBox(height: Space.md),
                Text(
                  widget.accountEmail!,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showTextEditor({
    required String title,
    required String initialValue,
    required Key fieldKey,
    required String? Function(String) validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) => showTextEditorSheet(
    context: context,
    title: title,
    initialValue: initialValue,
    fieldKey: fieldKey,
    validator: validator,
    textCapitalization: textCapitalization,
  );

  Future<double?> _showNumberEditor({
    required String title,
    required double initialValue,
    required Key fieldKey,
    required double min,
    required double max,
    required String rangeError,
    String? prefixText,
    String? suffixText,
  }) => showNumberEditorSheet(
    context: context,
    title: title,
    initialValue: initialValue,
    fieldKey: fieldKey,
    min: min,
    max: max,
    rangeError: rangeError,
    prefixText: prefixText,
    suffixText: suffixText,
  );

  Future<T?> _showChoice<T>({
    required String title,
    required T current,
    required List<T> values,
    required String Function(T) label,
  }) => showChoiceSheet<T>(
    context: context,
    title: title,
    current: current,
    values: values,
    label: label,
  );

  static String _efficiencyUnit(EnergySource source) =>
      source == EnergySource.electric ? 'mi/kWh' : 'MPG';

  static String _plain(double value) => plainNumber(value);
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // The shared heading rather than a style of its own. Settings had drawn
      // these at onSurface/w800/12sp — heavier, darker and smaller than the
      // identical labels on Today, History and Coach — which read as a screen
      // from a different app. Going through the widget is what stops it
      // drifting again.
      Padding(
        padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
        child: SectionHeading(title: title.toUpperCase()),
      ),
      GlassSurface(
        padding: EdgeInsets.zero,
        elevation: Elevation.flat,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 68),
                    child: Divider(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: .48),
                    ),
                  ),
                child,
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      leading: SoftIcon(icon, size: 19),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 142),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          if (onTap != null) ...[
            const SizedBox(width: Space.xs),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.onSurfaceVariant,
              size: 20,
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

class _DrivingCostSummary extends StatelessWidget {
  const _DrivingCostSummary({required this.costs, required this.units});

  final DrivingCosts costs;
  final MeasurementUnits units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fuel = costs.fuelCostPerMile;
    final vehicle = costs.vehicleCostPerMile;
    final allIn = costs.allInCostPerMile;
    final distance = units.distance.singular;
    final fuelSwatch = colors.primary;
    final vehicleSwatch = colors.primary.withValues(alpha: .38);
    return GlassSurface(
      key: const ValueKey('settings-all-in-cost'),
      padding: const EdgeInsets.all(Space.xl),
      tint: colors.primaryContainer.withValues(alpha: .82),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'YOUR DRIVING COST',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              // The unit rides in the pill so the figure below is money alone:
              // at 32/w800 a trailing "/ mile" carried the same weight as the
              // amount and split the eye between them.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  'per $distance',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Space.gapLg,
          Text(
            units.cents(allIn),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFeatures: tabularFigures,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Fuel and vehicle wear on every $distance you drive.',
            style: theme.textTheme.bodySmall,
          ),
          Space.gapLg,
          // Both gaps belong to the bar: without it the legend would sit under
          // a double gap it did not ask for.
          if (allIn > 0) ...[
            _CostSplitBar(
              fuelShare: fuel / allIn,
              fuelSwatch: fuelSwatch,
              vehicleSwatch: vehicleSwatch,
            ),
            Space.gapLg,
          ],
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CostShare(
                    label: 'Fuel',
                    amount: units.cents(fuel),
                    share: allIn > 0 ? fuel / allIn : 0,
                    swatch: fuelSwatch,
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: Space.lg),
                  color: colors.onSurface.withValues(alpha: .09),
                ),
                Expanded(
                  child: _CostShare(
                    label: 'Vehicle',
                    amount: units.cents(vehicle),
                    share: allIn > 0 ? vehicle / allIn : 0,
                    swatch: vehicleSwatch,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The fuel/vehicle split as one unbroken pill, the two shares meeting at the
/// split. The rounding lives on the outer clip so the join stays seamless.
class _CostSplitBar extends StatelessWidget {
  const _CostSplitBar({
    required this.fuelShare,
    required this.fuelSwatch,
    required this.vehicleSwatch,
  });

  final double fuelShare;
  final Color fuelSwatch;
  final Color vehicleSwatch;

  @override
  Widget build(BuildContext context) {
    final fuelFlex = (fuelShare * 1000).round().clamp(0, 1000);
    final vehicleFlex = 1000 - fuelFlex;
    // A share worth nothing is left out rather than given a hairline: a sliver
    // of the other colour at the end of the bar reads as a rendering fault.
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: SizedBox(
        height: 8,
        child: Row(
          // Stretch, or a childless ColoredBox collapses to nothing.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fuelFlex > 0)
              Expanded(
                flex: fuelFlex,
                child: ColoredBox(color: fuelSwatch),
              ),
            if (vehicleFlex > 0)
              Expanded(
                flex: vehicleFlex,
                child: ColoredBox(color: vehicleSwatch),
              ),
          ],
        ),
      ),
    );
  }
}

class _CostShare extends StatelessWidget {
  const _CostShare({
    required this.label,
    required this.amount,
    required this.share,
    required this.swatch,
  });

  final String label;
  final String amount;
  final double share;
  final Color swatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
            ),
            const SizedBox(width: Space.sm),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        // Amount and share share one line: as a third stacked line the
        // percentage doubled the column's height to caption a number that is
        // already next to its own bar segment.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            Text(
              '${(share * 100).round()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExpenseCategoryCard extends StatelessWidget {
  const _ExpenseCategoryCard({
    required this.category,
    required this.amount,
    required this.units,
    required this.coveredByMileageRate,
  });

  final ExpenseCategory category;

  /// What the driver has recorded under this category this year.
  final double amount;
  final MeasurementUnits units;

  /// True when this is a vehicle cost *and* the standard mileage rate is
  /// winning, so the amount is real but not separately claimable.
  final bool coveredByMileageRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final used = amount > 0;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: used
            ? colors.surfaceContainerHighest.withValues(alpha: .35)
            : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  coveredByMileageRate
                      ? '${category.scheduleCLine} · covered by the mileage rate'
                      : category.scheduleCLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          if (used)
            Text(
              units.cents(amount),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                // Struck through would be wrong — the money was spent. Muted
                // says "counted, but not on top of the rate".
                color: coveredByMileageRate
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
              ),
            ),
          if (category.isVehicleCost) ...[
            const SizedBox(width: Space.sm),
            Icon(
              Icons.directions_car_rounded,
              size: 18,
              color: coveredByMileageRate
                  ? colors.onSurfaceVariant
                  : colors.primary,
            ),
          ],
        ],
      ),
    );
  }
}
