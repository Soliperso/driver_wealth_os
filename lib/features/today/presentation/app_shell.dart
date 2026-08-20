import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/backend_config.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../admin/application/admin_repository.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../accounts/application/earnings_connection_gateway.dart';
import '../../accounts/application/earnings_repository.dart';
import '../../accounts/domain/work_platform.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../accounts/presentation/work_accounts_screen.dart';
import '../../coach/presentation/coach_screen.dart';
import '../../driving/application/driving_session_controller.dart';
import '../../driving/application/location_tracker.dart';
import '../../driving/domain/driving_session.dart';
import '../../driving/presentation/location_disclosure_sheet.dart';
import '../../freedom/domain/freedom_goal.dart';
import '../../freedom/presentation/freedom_screen.dart';
import '../../history/presentation/history_screen.dart';
import '../../history/presentation/shift_detail_screen.dart';
import '../../settings/domain/driving_costs.dart';
import '../../settings/domain/distance_unit.dart';
import '../../settings/application/shift_export.dart';
import '../../settings/presentation/privacy_security_screen.dart';
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
    required this.drivingCosts,
    required this.hourlyFloor,
    required this.weekStartsOn,
    required this.drivingDaysPerWeek,
    required this.distanceUnit,
    required this.freedomGoal,
    required this.onShiftAdded,
    required this.onShiftUpdated,
    required this.onShiftDeleted,
    required this.onDailyGoalChanged,
    required this.onVehicleCostPerMileChanged,
    required this.onEnergySourceChanged,
    required this.onFuelEfficiencyChanged,
    required this.onFuelPriceChanged,
    required this.onHourlyFloorChanged,
    required this.onWeekStartsOnChanged,
    required this.onDrivingDaysPerWeekChanged,
    required this.onDistanceUnitChanged,
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
    this.adminRepository,
  });
  final String driverName;
  final List<Shift> shifts;
  final double dailyGoal;
  final double vehicleCostPerMile;
  final DrivingCosts drivingCosts;
  final double hourlyFloor;
  final int weekStartsOn;
  final int drivingDaysPerWeek;
  final DistanceUnit distanceUnit;
  final FreedomGoal? freedomGoal;
  final ValueChanged<Shift> onShiftAdded;
  final ValueChanged<Shift> onShiftUpdated;
  final ValueChanged<String> onShiftDeleted;
  final ValueChanged<double> onDailyGoalChanged;
  final ValueChanged<double> onVehicleCostPerMileChanged;
  final ValueChanged<EnergySource> onEnergySourceChanged;
  final ValueChanged<double> onFuelEfficiencyChanged;
  final ValueChanged<double> onFuelPriceChanged;
  final ValueChanged<double> onHourlyFloorChanged;
  final ValueChanged<int> onWeekStartsOnChanged;
  final ValueChanged<int> onDrivingDaysPerWeekChanged;
  final ValueChanged<DistanceUnit> onDistanceUnitChanged;
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

  /// Non-null only after the backend confirms this account owns the platform.
  final AdminRepository? adminRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

/// Asked at the start of a session, and again whenever the driver switches
/// another app on mid-shift, so the tracked shift knows what it was running
/// rather than making the driver recall it hours later.
///
/// Two ways out on purpose. Tapping a row picks that app and closes — the one
/// tap most shifts need. The trailing `+` instead adds it to a running
/// selection and keeps the sheet open, which is how a driver says "Uber *and*
/// Lyft" without the common case paying for the rare one.
class _PlatformPickerSheet extends StatefulWidget {
  const _PlatformPickerSheet({
    required this.title,
    required this.subtitle,
    this.already = const {},
  });

  final String title;
  final String subtitle;

  /// Apps already running. Shown ticked and inert rather than hidden, so the
  /// sheet reads as the whole picture of what is on.
  final Set<WorkPlatform> already;

  @override
  State<_PlatformPickerSheet> createState() => _PlatformPickerSheetState();
}

class _PlatformPickerSheetState extends State<_PlatformPickerSheet> {
  /// Insertion-ordered, because the order the driver picks them in is the
  /// order their earnings rows appear in afterwards.
  final _selected = <WorkPlatform>{};

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        // Tall enough that picking one app leaves the rest reachable, short
        // enough that the sheet still reads as a sheet.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
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
                      _PlatformPickerRow(
                        platform: platform,
                        selected: _selected.contains(platform),
                        running: widget.already.contains(platform),
                        onPick: () =>
                            Navigator.of(context).pop(<WorkPlatform>{platform}),
                        onToggle: () => setState(() {
                          if (!_selected.remove(platform)) {
                            _selected.add(platform);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              // Appears only once the driver has started building a combination.
              // Until then the sheet is exactly what it was before.
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('start-selected-platforms'),
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(Set<WorkPlatform>.of(_selected)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                    _selected
                        .map((platform) => platform.displayName)
                        .join(' + '),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Both apps share one shift — your hours and miles are only '
                  'counted once.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformPickerRow extends StatelessWidget {
  const _PlatformPickerRow({
    required this.platform,
    required this.selected,
    required this.running,
    required this.onPick,
    required this.onToggle,
  });

  final WorkPlatform platform;
  final bool selected;
  final bool running;
  final VoidCallback onPick;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey('start-platform-${platform.id}'),
      contentPadding: EdgeInsets.zero,
      enabled: !running,
      leading: PlatformLogo(platform: platform, size: 38),
      title: Text(platform.displayName),
      subtitle: running ? const Text('Already running') : null,
      onTap: running ? null : onPick,
      trailing: running
          ? Icon(Icons.check_circle_rounded, color: colors.primary)
          : IconButton(
              key: ValueKey('add-platform-${platform.id}'),
              onPressed: onToggle,
              tooltip: selected
                  ? 'Remove ${platform.displayName}'
                  : 'Also run ${platform.displayName}',
              icon: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
    );
  }
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
        onPauseDriving: widget.drivingController == null ? null : _pauseDriving,
        onResumeDriving: widget.drivingController == null
            ? null
            : _resumeDriving,
        onAutoEndShift: widget.drivingController == null ? null : _autoEndShift,
        onUpgradeBackground: widget.drivingController == null
            ? null
            : _upgradeBackground,
        onAddDrivingPlatform: widget.drivingController == null
            ? null
            : _addDrivingPlatform,
        onRemoveDrivingPlatform: widget.drivingController == null
            ? null
            : _removeDrivingPlatform,
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
        hourlyFloor: widget.hourlyFloor,
        weekStartsOn: widget.weekStartsOn,
        drivingDaysPerWeek: widget.drivingDaysPerWeek,
      ),
      _ => SettingsScreen(
        driverName: widget.driverName,
        dailyGoal: widget.dailyGoal,
        drivingCosts: widget.drivingCosts,
        hourlyFloor: widget.hourlyFloor,
        weekStartsOn: widget.weekStartsOn,
        drivingDaysPerWeek: widget.drivingDaysPerWeek,
        distanceUnit: widget.distanceUnit,
        onDriverNameChanged: widget.onDriverNameChanged,
        onDailyGoalChanged: widget.onDailyGoalChanged,
        onVehicleCostPerMileChanged: widget.onVehicleCostPerMileChanged,
        onEnergySourceChanged: widget.onEnergySourceChanged,
        onFuelEfficiencyChanged: widget.onFuelEfficiencyChanged,
        onFuelPriceChanged: widget.onFuelPriceChanged,
        onHourlyFloorChanged: widget.onHourlyFloorChanged,
        onWeekStartsOnChanged: widget.onWeekStartsOnChanged,
        onDrivingDaysPerWeekChanged: widget.onDrivingDaysPerWeekChanged,
        onDistanceUnitChanged: widget.onDistanceUnitChanged,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        accountEmail: widget.accountEmail,
        onSignOut: widget.onSignOut == null ? null : _confirmSignOut,
        onConnectAccounts: _connectAccounts,
        onExportData: _exportData,
        onOpenPrivacy: _openPrivacy,
        onOpenAdmin: widget.adminRepository == null ? null : _openAdmin,
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

  void _openAdmin() {
    final repository = widget.adminRepository;
    if (repository == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminDashboardScreen(repository: repository),
      ),
    );
  }

  /// Switches another app on mid-shift, from the live session card.
  ///
  /// Same sheet as the start flow, with what is already running shown ticked
  /// and inert. Nothing about the clock, the mileage or a break is touched.
  Future<void> _addDrivingPlatform() async {
    final controller = widget.drivingController;
    final session = controller?.session;
    if (controller == null || session == null) return;

    final picked = await showModalBottomSheet<Set<WorkPlatform>>(
      context: context,
      showDragHandle: true,
      // Otherwise the sheet is capped at half the screen, and the confirm
      // button appearing shrinks the list enough to push apps out of view at
      // the moment the driver is trying to pick a second one.
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _PlatformPickerSheet(
        title: 'Add another app',
        subtitle:
            'Your hours and miles keep counting once — only the earnings are '
            'recorded per app.',
        already: session.livePlatforms.toSet(),
      ),
    );
    if (picked == null || !mounted) return;
    for (final platform in picked) {
      await controller.addPlatform(platform);
    }
  }

  Future<void> _removeDrivingPlatform(WorkPlatform platform) async {
    await widget.drivingController?.removePlatform(platform);
  }

  Future<void> _startDriving() async {
    final controller = widget.drivingController;
    if (controller == null) return;

    final platforms = await showModalBottomSheet<Set<WorkPlatform>>(
      context: context,
      showDragHandle: true,
      // See the note in [_addDrivingPlatform]: the default half-screen cap
      // loses rows exactly when a second app is being picked.
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const _PlatformPickerSheet(
        title: 'Which apps are you running?',
        subtitle:
            'Pick one, or add more if you are running several at once. You '
            'can change this any time during the shift.',
      ),
    );
    if (platforms == null || platforms.isEmpty || !mounted) return;

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
      platforms: platforms,
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

  /// Breaks are taken and ended without ceremony — no sheet, no confirmation.
  /// Both are trivially reversible, and a driver pulling over for ten minutes
  /// should not have to read a dialog first.
  Future<void> _pauseDriving() async => widget.drivingController?.pause();

  Future<void> _resumeDriving() async => widget.drivingController?.resume();

  /// A break that ran past the limit while the app was open.
  ///
  /// Unlike [_endShift] this does not open the earnings screen: it fires on a
  /// timer, with nobody necessarily looking, and throwing a form in front of
  /// whatever the driver was doing would be worse than letting them come back
  /// to it. The controller has already banked the draft, so the recovery card
  /// on Today is waiting for them.
  void _autoEndShift() {
    final controller = widget.drivingController;
    if (controller == null) return;
    unawaited(
      controller.endIfPauseExpired().then((draft) {
        if (draft == null || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Shift ended automatically after '
              '${pauseAutoEndAfter.inHours} hours paused. Add your earnings '
              'when you are ready.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }),
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

  Future<void> _exportData() async {
    if (widget.shifts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a shift before exporting data.')),
      );
      return;
    }
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final renderBox = context.findRenderObject();
    final origin = renderBox is RenderBox
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : null;
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Driver Wealth driving data',
        text: 'Your Driver Wealth shift export.',
        files: [
          XFile.fromData(
            utf8.encode(ShiftExport.csv(widget.shifts)),
            mimeType: 'text/csv',
          ),
        ],
        fileNameOverrides: ['driver-wealth-$date.csv'],
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _openPrivacy() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PrivacySecurityScreen(accountEmail: widget.accountEmail),
    ),
  );
}
