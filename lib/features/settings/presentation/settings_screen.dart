import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../tax/domain/expense.dart';
import '../domain/distance_unit.dart';
import '../domain/driving_costs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.driverName,
    required this.dailyGoal,
    required this.drivingCosts,
    required this.hourlyFloor,
    required this.weekStartsOn,
    required this.drivingDaysPerWeek,
    required this.distanceUnit,
    required this.onDriverNameChanged,
    required this.onDailyGoalChanged,
    required this.onVehicleCostPerMileChanged,
    required this.onEnergySourceChanged,
    required this.onFuelEfficiencyChanged,
    required this.onFuelPriceChanged,
    required this.onHourlyFloorChanged,
    required this.onWeekStartsOnChanged,
    required this.onDrivingDaysPerWeekChanged,
    required this.onDistanceUnitChanged,
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
  final double dailyGoal;
  final DrivingCosts drivingCosts;
  final double hourlyFloor;
  final int weekStartsOn;
  final int drivingDaysPerWeek;
  final DistanceUnit distanceUnit;
  final ValueChanged<String> onDriverNameChanged;
  final ValueChanged<double> onDailyGoalChanged;
  final ValueChanged<double> onVehicleCostPerMileChanged;
  final ValueChanged<EnergySource> onEnergySourceChanged;
  final ValueChanged<double> onFuelEfficiencyChanged;
  final ValueChanged<double> onFuelPriceChanged;
  final ValueChanged<double> onHourlyFloorChanged;
  final ValueChanged<int> onWeekStartsOnChanged;
  final ValueChanged<int> onDrivingDaysPerWeekChanged;
  final ValueChanged<DistanceUnit> onDistanceUnitChanged;
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
    final unit = widget.distanceUnit;
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
                  value: Money.whole(widget.dailyGoal),
                  onTap: _editDailyGoal,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-hourly-floor'),
                  icon: Icons.speed_rounded,
                  title: 'Minimum profitable rate',
                  value: '${Money.whole(widget.hourlyFloor)}/hr',
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
                      '${Money.cents(costs.fuelPrice)}/${costs.energySource.unit}',
                  onTap: _editFuelPrice,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-vehicle-rate'),
                  icon: Icons.directions_car_outlined,
                  title: 'Vehicle cost',
                  value:
                      '${Money.cents(unit.rateFromPerMile(costs.vehicleCostPerMile))}/${unit.symbol}',
                  onTap: _editVehicleRate,
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            _DrivingCostSummary(costs: costs, unit: unit),
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
                  key: const ValueKey('settings-distance-unit'),
                  icon: Icons.straighten_rounded,
                  title: 'Distance units',
                  value: unit.label,
                  onTap: _chooseDistanceUnit,
                ),
                _SettingsTile(
                  key: const ValueKey('settings-expense-categories'),
                  icon: Icons.receipt_long_rounded,
                  title: 'Expense categories',
                  subtitle: 'Deductible business expenses',
                  value: '${ExpenseCategory.values.length}',
                  onTap: _showExpenseCategories,
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
                // if (widget.onConnectAccounts != null)
                //   _SettingsTile(
                //     key: const ValueKey('settings-work-accounts'),
                //     icon: Icons.link_rounded,
                //     title: 'Work accounts',
                //     onTap: widget.onConnectAccounts,
                //   ),
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
      prefixText: '\$ ',
      suffixText: '/ day',
      min: 1,
      max: 100000,
      rangeError: 'Enter an amount between \$1 and \$100,000',
    );
    if (value != null) widget.onDailyGoalChanged(value);
  }

  Future<void> _editHourlyFloor() async {
    final value = await _showNumberEditor(
      title: 'Minimum profitable rate',
      initialValue: widget.hourlyFloor,
      fieldKey: const ValueKey('settings-hourly-floor-field'),
      prefixText: '\$ ',
      suffixText: '/ hr',
      min: 1,
      max: 10000,
      rangeError: 'Enter an amount between \$1 and \$10,000',
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
      prefixText: '\$ ',
      suffixText: '/ ${costs.energySource.unit}',
      min: 0,
      max: 100,
      rangeError: 'Enter a price between \$0 and \$100',
    );
    if (value != null) widget.onFuelPriceChanged(value);
  }

  Future<void> _editVehicleRate() async {
    final unit = widget.distanceUnit;
    final value = await _showNumberEditor(
      title: 'Vehicle cost',
      initialValue: unit.rateFromPerMile(
        widget.drivingCosts.vehicleCostPerMile,
      ),
      fieldKey: const ValueKey('settings-vehicle-rate-field'),
      prefixText: '\$ ',
      suffixText: '/ ${unit.symbol}',
      min: 0,
      max: 100,
      rangeError: 'Enter a rate between \$0 and \$100',
    );
    if (value != null) {
      widget.onVehicleCostPerMileChanged(unit.rateToPerMile(value));
    }
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

  Future<void> _chooseDistanceUnit() async {
    final selected = await _showChoice<DistanceUnit>(
      title: 'Distance units',
      current: widget.distanceUnit,
      values: DistanceUnit.values,
      label: (unit) => unit.label,
    );
    if (selected != null) widget.onDistanceUnitChanged(selected);
  }

  Future<void> _showExpenseCategories() async {
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
                'Costs you can deduct on Schedule C. Vehicle costs marked below cannot be claimed alongside the standard mileage rate.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: Space.lg),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: ExpenseCategory.values.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (context, index) => _ExpenseCategoryCard(
                    category: ExpenseCategory.values[index],
                  ),
                ),
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
  }) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _TextEditorSheet(
      title: title,
      initialValue: initialValue,
      fieldKey: fieldKey,
      validator: validator,
      textCapitalization: textCapitalization,
    ),
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
  }) => showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NumberEditorSheet(
      title: title,
      initialValue: initialValue,
      fieldKey: fieldKey,
      min: min,
      max: max,
      rangeError: rangeError,
      prefixText: prefixText,
      suffixText: suffixText,
    ),
  );

  Future<T?> _showChoice<T>({
    required String title,
    required T current,
    required List<T> values,
    required String Function(T) label,
  }) => showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.sm,
                Space.xl,
                Space.md,
              ),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final value in values)
              ListTile(
                title: Text(label(value)),
                trailing: value == current
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    ),
  );

  static String _efficiencyUnit(EnergySource source) =>
      source == EnergySource.electric ? 'mi/kWh' : 'MPG';

  static String _plain(double value) => value.toStringAsFixed(
    value.truncateToDouble() == value
        ? 0
        : value < 1
        ? 3
        : 1,
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
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
  const _DrivingCostSummary({required this.costs, required this.unit});

  final DrivingCosts costs;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fuel = unit.rateFromPerMile(costs.fuelCostPerMile);
    final vehicle = unit.rateFromPerMile(costs.vehicleCostPerMile);
    final allIn = unit.rateFromPerMile(costs.allInCostPerMile);
    final distance = unit == DistanceUnit.miles ? 'mile' : 'km';
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
            Money.cents(allIn),
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
                    amount: Money.cents(fuel),
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
                    amount: Money.cents(vehicle),
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
              Expanded(flex: fuelFlex, child: ColoredBox(color: fuelSwatch)),
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
  const _ExpenseCategoryCard({required this.category});

  final ExpenseCategory category;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.scheduleCLine,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (category.isVehicleCost)
            Icon(
              Icons.directions_car_rounded,
              size: 18,
              color: colors.primary,
            ),
        ],
      ),
    );
  }
}

class _TextEditorSheet extends StatefulWidget {
  const _TextEditorSheet({
    required this.title,
    required this.initialValue,
    required this.fieldKey,
    required this.validator,
    required this.textCapitalization,
  });

  final String title;
  final String initialValue;
  final Key fieldKey;
  final String? Function(String) validator;
  final TextCapitalization textCapitalization;

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.validator(_controller.text);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) => _EditorSheet(
    title: widget.title,
    onDone: _submit,
    child: TextField(
      key: widget.fieldKey,
      controller: _controller,
      autofocus: true,
      textCapitalization: widget.textCapitalization,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: widget.title,
        errorText: _errorText,
      ),
      onSubmitted: (_) => _submit(),
    ),
  );
}

class _NumberEditorSheet extends StatefulWidget {
  const _NumberEditorSheet({
    required this.title,
    required this.initialValue,
    required this.fieldKey,
    required this.min,
    required this.max,
    required this.rangeError,
    this.prefixText,
    this.suffixText,
  });

  final String title;
  final double initialValue;
  final Key fieldKey;
  final double min;
  final double max;
  final String rangeError;
  final String? prefixText;
  final String? suffixText;

  @override
  State<_NumberEditorSheet> createState() => _NumberEditorSheetState();
}

class _NumberEditorSheetState extends State<_NumberEditorSheet> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _SettingsScreenState._plain(widget.initialValue),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null ||
        !value.isFinite ||
        value < widget.min ||
        value > widget.max) {
      setState(() => _errorText = widget.rangeError);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => _EditorSheet(
    title: widget.title,
    onDone: _submit,
    child: TextField(
      key: widget.fieldKey,
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: widget.title,
        prefixText: widget.prefixText,
        suffixText: widget.suffixText,
        errorText: _errorText,
      ),
      onSubmitted: (_) => _submit(),
    ),
  );
}

class _EditorSheet extends StatelessWidget {
  const _EditorSheet({
    required this.title,
    required this.child,
    required this.onDone,
  });

  final String title;
  final Widget child;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        Space.sm,
        Space.xl,
        MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.lg),
          child,
          const SizedBox(height: Space.lg),
          FilledButton(
            key: const ValueKey('settings-editor-done'),
            onPressed: onDone,
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}
