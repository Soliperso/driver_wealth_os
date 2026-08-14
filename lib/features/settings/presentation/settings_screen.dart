import 'package:flutter/material.dart';

import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.driverName,
    required this.dailyGoal,
    required this.vehicleCostPerMile,
    required this.onDriverNameChanged,
    required this.onDailyGoalChanged,
    required this.onVehicleCostPerMileChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.accountEmail,
    this.onSignOut,
    this.onConnectAccounts,
  });

  final String driverName;
  final double dailyGoal;
  final double vehicleCostPerMile;
  final ValueChanged<String> onDriverNameChanged;
  final ValueChanged<double> onDailyGoalChanged;
  final ValueChanged<double> onVehicleCostPerMileChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// The signed-in account. Null in a local-only build, where there is no
  /// account to show and nothing to sign out of.
  final String? accountEmail;
  final Future<void> Function()? onSignOut;

  /// Work accounts were previously reachable only from a card on Today, which
  /// disappears once the driver has shifts.
  final VoidCallback? onConnectAccounts;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _dailyGoal;
  late final TextEditingController _vehicleRate;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.driverName);
    _dailyGoal = TextEditingController(text: _money(widget.dailyGoal));
    _vehicleRate = TextEditingController(
      text: widget.vehicleCostPerMile.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    for (final controller in [_name, _dailyGoal, _vehicleRate]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SoftScaffold(
      title: 'Settings',
      body: PageFrame(
        maxWidth: 680,
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              GlassSurface(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Your details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter your name'
                          : null,
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
                      'Profit targets and costs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These apply to every shift, including any imported from a connected account.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('settings-daily-goal'),
                      controller: _dailyGoal,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Daily profit goal',
                        prefixText: '\$ ',
                        prefixIcon: Icon(Icons.flag_outlined),
                      ),
                      validator: (input) {
                        final parsed = double.tryParse(input?.trim() ?? '');
                        if (parsed == null ||
                            !parsed.isFinite ||
                            parsed <= 0 ||
                            parsed > 100000) {
                          return 'Enter an amount between \$1 and \$100,000';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('settings-vehicle-rate'),
                      controller: _vehicleRate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Vehicle wear per mile',
                        prefixText: '\$ ',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                        helperText:
                            'Maintenance, tyres and depreciation only — not fuel.',
                        helperMaxLines: 2,
                      ),
                      validator: (input) {
                        final parsed = double.tryParse(input?.trim() ?? '');
                        if (parsed == null ||
                            !parsed.isFinite ||
                            parsed < 0 ||
                            parsed > 100) {
                          return 'Enter a rate between \$0 and \$100';
                        }
                        return null;
                      },
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
                      'Appearance',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Both themes were fully designed but the app was pinned to
                    // whatever the system said, with no way to choose.
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_rounded),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_rounded),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_rounded),
                        ),
                      ],
                      selected: {widget.themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          widget.onThemeModeChanged(selection.first),
                    ),
                  ],
                ),
              ),
              if (widget.onConnectAccounts != null) ...[
                const SizedBox(height: 16),
                GlassSurface(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Work accounts',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Import earnings automatically instead of typing them.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('settings-work-accounts'),
                        onPressed: widget.onConnectAccounts,
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('Manage work accounts'),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.accountEmail != null || widget.onSignOut != null) ...[
                const SizedBox(height: 16),
                GlassSurface(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Account',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.accountEmail == null
                            ? 'Signed in.'
                            : 'Signed in as ${widget.accountEmail}.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your shifts and goals are saved to this account, so '
                        'they survive a new phone or a reinstall.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (widget.onSignOut != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const ValueKey('settings-sign-out'),
                          onPressed: () => widget.onSignOut!(),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Sign out'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                key: const ValueKey('settings-save'),
                onPressed: _save,
                child: const Text('Save settings'),
              ),
              const SizedBox(height: 12),
              Text(
                'Driver Wealth never changes your work accounts or accepts jobs for you.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 92),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.onDriverNameChanged(_name.text);
    widget.onDailyGoalChanged(double.parse(_dailyGoal.text.trim()));
    widget.onVehicleCostPerMileChanged(double.parse(_vehicleRate.text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  static String _money(double value) =>
      value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
}
