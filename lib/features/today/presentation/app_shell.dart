import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/application/earnings_connection_gateway.dart';
import '../../accounts/application/earnings_repository.dart';
import '../../accounts/domain/work_platform.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../accounts/presentation/work_accounts_screen.dart';
import '../../coach/presentation/coach_screen.dart';
import '../../driving/application/driving_session_controller.dart';
import '../../freedom/domain/freedom_goal.dart';
import '../../freedom/presentation/freedom_screen.dart';
import '../../history/presentation/history_screen.dart';
import '../../history/presentation/shift_detail_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/presentation/add_shift_screen.dart';
import 'today_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.driverName,
    required this.shifts,
    required this.dailyGoal,
    required this.vehicleCostPerMile,
    required this.freedomGoal,
    required this.onShiftAdded,
    required this.onShiftUpdated,
    required this.onShiftDeleted,
    required this.onDailyGoalChanged,
    required this.onVehicleCostPerMileChanged,
    required this.onDriverNameChanged,
    required this.onFreedomGoalChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.syncStatus,
    this.onRefreshEarnings,
    this.drivingController,
    this.drivingRefreshInterval = const Duration(seconds: 1),
  });
  final String driverName;
  final List<Shift> shifts;
  final double dailyGoal;
  final double vehicleCostPerMile;
  final FreedomGoal? freedomGoal;
  final ValueChanged<Shift> onShiftAdded;
  final ValueChanged<Shift> onShiftUpdated;
  final ValueChanged<String> onShiftDeleted;
  final ValueChanged<double> onDailyGoalChanged;
  final ValueChanged<double> onVehicleCostPerMileChanged;
  final ValueChanged<String> onDriverNameChanged;
  final ValueChanged<FreedomGoal?> onFreedomGoalChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final SyncStatus? syncStatus;
  final Future<void> Function()? onRefreshEarnings;
  final DrivingSessionController? drivingController;
  final Duration? drivingRefreshInterval;

  @override
  State<AppShell> createState() => _AppShellState();
}

/// Asked once at the start of a session so the tracked shift knows which
/// platform it belongs to, rather than making the driver recall it hours later.
class _PlatformPickerSheet extends StatelessWidget {
  const _PlatformPickerSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Which platform?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'You can change this when you enter your earnings.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // The full platform list is taller than a sheet on a small phone,
          // so it scrolls rather than overflowing.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final platform in WorkPlatform.values)
                  ListTile(
                    key: ValueKey('start-platform-${platform.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: PlatformLogo(platform: platform, size: 38),
                    title: Text(platform.displayName),
                    onTap: () => Navigator.of(context).pop(platform),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.drivingController?.addListener(_onDrivingChanged);
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drivingController != widget.drivingController) {
      oldWidget.drivingController?.removeListener(_onDrivingChanged);
      widget.drivingController?.addListener(_onDrivingChanged);
    }
  }

  @override
  void dispose() {
    widget.drivingController?.removeListener(_onDrivingChanged);
    super.dispose();
  }

  /// Mileage accrues while the driver is elsewhere, so the shell repaints on
  /// every counted leg rather than only when they interact with it.
  void _onDrivingChanged() {
    if (mounted) setState(() {});
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Today',
    ),
    NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
    NavigationDestination(
      icon: Icon(Icons.flag_outlined),
      selectedIcon: Icon(Icons.flag_rounded),
      label: 'Freedom',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome_rounded),
      label: 'Coach',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final content = switch (_index) {
      0 => TodayScreen(
        driverName: widget.driverName,
        shifts: widget.shifts,
        dailyGoal: widget.dailyGoal,
        onAddShift: () => _addShift(returnToToday: true),
        onConnectAccounts: _connectAccounts,
        onDailyGoalChanged: widget.onDailyGoalChanged,
        onOpenShift: _openShift,
        onOpenSettings: () => setState(() => _index = 4),
        onRefresh: widget.onRefreshEarnings,
        drivingSession: widget.drivingController?.session,
        drivingBackgroundLimited:
            widget.drivingController?.backgroundLimited ?? false,
        onStartDriving: widget.drivingController == null ? null : _startDriving,
        onEndShift: widget.drivingController == null ? null : _endShift,
        drivingRefreshInterval: widget.drivingRefreshInterval,
      ),
      1 => HistoryScreen(
        shifts: widget.shifts,
        onAddShift: () => _addShift(returnToToday: false),
        onShiftUpdated: widget.onShiftUpdated,
        onShiftDeleted: widget.onShiftDeleted,
      ),
      2 => FreedomScreen(
        shifts: widget.shifts,
        goal: widget.freedomGoal,
        onGoalChanged: widget.onFreedomGoalChanged,
      ),
      3 => CoachScreen(
        shifts: widget.shifts,
        dailyGoal: widget.dailyGoal,
        freedomGoal: widget.freedomGoal,
      ),
      _ => SettingsScreen(
        driverName: widget.driverName,
        dailyGoal: widget.dailyGoal,
        vehicleCostPerMile: widget.vehicleCostPerMile,
        onDriverNameChanged: widget.onDriverNameChanged,
        onDailyGoalChanged: widget.onDailyGoalChanged,
        onVehicleCostPerMileChanged: widget.onVehicleCostPerMileChanged,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
    };
    if (!wide) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(children: [const SoftBackground(), content]),
        bottomNavigationBar: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: .88),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .35),
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                destinations: _destinations,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const SoftBackground(),
          Row(
            children: [
              SafeArea(
                child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(26),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: .82),
                      child: NavigationRail(
                        selectedIndex: _index,
                        labelType: NavigationRailLabelType.all,
                        leading: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: BrandMark(size: 42, showShadow: false),
                        ),
                        destinations: _destinations
                            .map(
                              (d) => NavigationRailDestination(
                                icon: d.icon,
                                selectedIcon: d.selectedIcon,
                                label: Text(d.label),
                              ),
                            )
                            .toList(),
                        onDestinationSelected: (value) =>
                            setState(() => _index = value),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _startDriving() async {
    final controller = widget.drivingController;
    if (controller == null) return;

    final platform = await showModalBottomSheet<WorkPlatform>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const _PlatformPickerSheet(),
    );
    if (platform == null || !mounted) return;

    final result = await controller.start(
      platform: platform,
      vehicleCostPerMile: widget.vehicleCostPerMile,
    );
    if (!mounted) return;
    if (result.isStarted) {
      setState(() => _index = 0);
      return;
    }
    // Location is the whole feature, so a refusal is explained rather than
    // silently leaving the driver on a screen where nothing happened.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result.failure!) {
          StartFailure.serviceDisabled =>
            'Turn on location services to track miles.',
          StartFailure.permissionDenied =>
            'Driver Wealth needs location access to track your miles.',
          StartFailure.permissionDeniedForever =>
            'Location is blocked. Enable it for Driver Wealth in Settings.',
        }),
      ),
    );
  }

  Future<void> _endShift() async {
    final controller = widget.drivingController;
    if (controller == null) return;
    final draft = await controller.end();
    if (draft == null || !mounted) return;

    // The session supplies hours and miles; the money is still the driver's
    // to enter until an earnings source can supply it.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddShiftScreen(
          initialShift: draft,
          isNewFromSession: true,
          onSave: widget.onShiftAdded,
        ),
      ),
    );
    if (mounted) setState(() => _index = 0);
  }

  void _openShift(Shift shift) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShiftDetailScreen(
          shift: shift,
          onUpdated: widget.onShiftUpdated,
          onDeleted: widget.onShiftDeleted,
        ),
      ),
    );
  }

  Future<void> _addShift({required bool returnToToday}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddShiftScreen(
          onSave: widget.onShiftAdded,
          defaultVehicleCostPerMile: widget.vehicleCostPerMile,
        ),
      ),
    );
    if (returnToToday) setState(() => _index = 0);
  }

  Future<void> _connectAccounts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkAccountsScreen(
          connectionGateway:
              BackendConfig.isConfigured && BackendConfig.incomeSyncEnabled
              ? const SupabaseArgyleConnectionGateway()
              : const SetupRequiredConnectionGateway(),
          syncStatus: widget.syncStatus,
          onRefreshEarnings: widget.onRefreshEarnings,
        ),
      ),
    );
    // A connection only matters once its earnings are visible, so pull them
    // in as soon as the driver comes back from the connection flow.
    await widget.onRefreshEarnings?.call();
  }
}
