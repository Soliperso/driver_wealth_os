import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/application/earnings_connection_gateway.dart';
import '../../accounts/application/earnings_repository.dart';
import '../../accounts/domain/work_platform.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../accounts/presentation/work_accounts_screen.dart';
import '../../coach/presentation/coach_screen.dart';
import '../../driving/application/driving_session_controller.dart';
import '../../driving/application/location_tracker.dart';
import '../../driving/presentation/location_disclosure_sheet.dart';
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
    this.pendingDraft,
    this.onPendingDraftChanged,
    this.storageError,
    this.accountEmail,
    this.onSignOut,
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

  /// A tracked shift whose earnings were never entered. Offered for recovery
  /// instead of being discarded — the driving cannot be done again.
  final Shift? pendingDraft;
  final ValueChanged<Shift?>? onPendingDraftChanged;

  /// Non-null when writing to device storage failed.
  final String? storageError;

  /// The signed-in account, shown so the driver can tell which one they are
  /// looking at. Null in a local-only build.
  final String? accountEmail;
  final Future<void> Function()? onSignOut;

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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.drivingController?.addListener(_onDrivingChanged);
  }

  /// Location permission and the stream subscription can both change while the
  /// app is in the background, and neither reports back. Coming to the
  /// foreground is the app's only chance to notice.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(widget.drivingController?.refreshAfterResume());
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
    WidgetsBinding.instance.removeObserver(this);
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
        drivingTrackingInterrupted:
            widget.drivingController?.trackingInterrupted ?? false,
        onStartDriving: widget.drivingController == null ? null : _startDriving,
        onEndShift: widget.drivingController == null ? null : _endShift,
        onUpgradeBackground: widget.drivingController == null
            ? null
            : _upgradeBackground,
        drivingRefreshInterval: widget.drivingRefreshInterval,
        pendingDraft: widget.pendingDraft,
        onResumeDraft: widget.pendingDraft == null
            ? null
            : () => _enterEarnings(widget.pendingDraft!),
        onDiscardDraft: widget.pendingDraft == null
            ? null
            : _discardPendingDraft,
        storageError: widget.storageError,
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
        accountEmail: widget.accountEmail,
        onSignOut: widget.onSignOut == null ? null : _confirmSignOut,
        onConnectAccounts: _connectAccounts,
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

    // Explain before the OS asks. Play policy requires a prominent disclosure
    // ahead of a background-location request, and a driver deserves to know
    // what is being collected before the system dialog gives them two words
    // and two buttons.
    if (await controller.needsPermissionRequest()) {
      if (!mounted) return;
      final agreed = await LocationDisclosureSheet.show(context);
      if (!agreed || !mounted) return;
    }

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
    // silently leaving the driver on a screen where nothing happened. When the
    // app can no longer fix it itself, the message carries a way out.
    final failure = result.failure!;
    final needsSettings =
        failure == StartFailure.permissionDeniedForever ||
        failure == StartFailure.serviceDisabled;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (failure) {
          StartFailure.serviceDisabled =>
            'Location services are off. Turn them on to track miles.',
          StartFailure.permissionDenied =>
            'Driver Wealth needs location access to track your miles. You can '
                'still enter a shift by hand.',
          StartFailure.permissionDeniedForever =>
            'Location is blocked for Driver Wealth. Only Settings can undo it.',
        }),
        duration: const Duration(seconds: 6),
        action: needsSettings
            ? SnackBarAction(
                label: 'Settings',
                onPressed: GeolocatorLocationTracker.openSettings,
              )
            : null,
      ),
    );
  }

  Future<void> _upgradeBackground() async {
    final controller = widget.drivingController;
    if (controller == null) return;
    final granted = await controller.upgradeToBackgroundTracking();
    if (!mounted) return;
    if (granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking the full shift now.')),
      );
      return;
    }
    // The OS may decline to re-prompt at all, in which case Settings is the
    // only route and saying so beats silently doing nothing.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Set location to “Always” for Driver Wealth to keep counting miles '
          'in the background.',
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: GeolocatorLocationTracker.openSettings,
        ),
      ),
    );
  }

  Future<void> _endShift() async {
    final controller = widget.drivingController;
    if (controller == null) return;
    final draft = await controller.end();
    if (draft == null || !mounted) return;

    // Banked before the earnings screen opens, not after it closes. The hours
    // and miles are already spent; if the driver backs out, or the OS kills
    // the app on that screen, the draft has to still be here.
    widget.onPendingDraftChanged?.call(draft);
    await _enterEarnings(draft);
  }

  /// Opens the earnings screen for a tracked draft. Saving retires the draft;
  /// anything else leaves it recoverable from Today.
  Future<void> _enterEarnings(Shift draft) async {
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

  Future<void> _confirmSignOut() async {
    // Signing out wipes this device's copy so the next person to sign in here
    // does not see the previous driver's earnings. Worth spelling out.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your shifts and goals stay on your account and come back when you '
          'sign in again. They will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-sign-out'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onSignOut?.call();
  }

  Future<void> _discardPendingDraft() async {
    final draft = widget.pendingDraft;
    if (draft == null) return;
    // Explicit confirmation: this is the one action that throws away tracked
    // driving, and it cannot be undone.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard tracked shift?'),
        content: Text(
          '${Money.hours(draft.hours)} and ${Money.number(draft.miles)} miles '
          'were tracked. Discarding this cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('confirm-discard-draft'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onPendingDraftChanged?.call(null);
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
