import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

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
import '../../history/presentation/history_screen.dart';
import '../../history/presentation/shift_detail_screen.dart';
import '../../settings/domain/driving_costs.dart';
import '../../settings/domain/driver_preferences.dart';
import '../../settings/domain/measurement_units.dart';
import '../../settings/application/history_export.dart';
import '../../settings/presentation/privacy_security_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/presentation/add_shift_screen.dart';
import '../../tax/application/receipt_store.dart';
import '../../tax/domain/expense.dart';
import '../../tax/presentation/tax_year_screen.dart';
import 'today_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.driverName,
    required this.shifts,
    required this.expenses,
    required this.onExpenseAdded,
    required this.onExpenseUpdated,
    required this.onExpenseDeleted,
    required this.dailyGoal,
    required this.vehicleCostPerMile,
    required this.drivingCosts,
    required this.hourlyFloor,
    required this.weekStartsOn,
    required this.drivingDaysPerWeek,
    required this.units,
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
    required this.onDriverNameChanged,
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
    this.onDeleteAccount,
    this.adminRepository,
    this.clock,
    this.receiptStore,
  });

  /// Injectable so a test can attach a receipt without a camera.
  final ReceiptStore? receiptStore;

  /// Permanently destroys the account. Null in a local-only build, where there
  /// is no account to destroy.
  final Future<void> Function()? onDeleteAccount;

  /// Injectable wall clock, passed down to the screens that anchor on "now".
  final DateTime Function()? clock;
  final String driverName;
  final List<Shift> shifts;
  final List<Expense> expenses;
  final ValueChanged<Expense> onExpenseAdded;
  final ValueChanged<Expense> onExpenseUpdated;
  final ValueChanged<String> onExpenseDeleted;
  final double dailyGoal;
  final double vehicleCostPerMile;
  final DrivingCosts drivingCosts;
  final double hourlyFloor;
  final int weekStartsOn;
  final int drivingDaysPerWeek;
  final MeasurementUnits units;
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
  final ValueChanged<String> onDriverNameChanged;
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
                  'Both apps share one session — your hours and miles are only '
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

  /// The settings the shell holds as loose fields, bundled into the shape the
  /// screens ask for.
  ///
  /// The shell still carries them one by one, so this is where they are
  /// reassembled. It no longer translates between two spellings of the same
  /// enum: there is one [MeasurementUnits] now, and it arrives ready to use.
  DriverPreferences get _preferences => DriverPreferences(
    driverName: widget.driverName,
    dailyGoal: widget.dailyGoal,
    drivingCosts: widget.drivingCosts,
    hourlyFloor: widget.hourlyFloor,
    weekStartsOn: widget.weekStartsOn,
    drivingDaysPerWeek: widget.drivingDaysPerWeek,
    units: widget.units,
  );

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Today',
    ),
    NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome_rounded),
      label: 'Coach',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: 'Taxes',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  /// Settings is the last tab, and adding one before it has moved this index
  /// once already. Named so the next insertion cannot silently send the driver
  /// to the wrong screen.
  static const _settingsIndex = 4;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final content = switch (_index) {
      0 => TodayScreen(
        driverName: widget.driverName,
        shifts: widget.shifts,
        clock: widget.clock,
        dailyGoal: widget.dailyGoal,
        onAddShift: () => _addShift(returnToToday: true),
        onDailyGoalChanged: widget.onDailyGoalChanged,
        onOpenShift: _openShift,
        onOpenHistory: () => setState(() => _index = 1),
        onOpenSettings: () => setState(() => _index = _settingsIndex),
        onRefresh: widget.onRefreshEarnings,
        drivingSession: widget.drivingController?.session,
        drivingBackgroundLimited:
            widget.drivingController?.backgroundLimited ?? false,
        drivingTrackingInterrupted:
            widget.drivingController?.trackingInterrupted ?? false,
        hourlyFloor: widget.hourlyFloor,
        units: _preferences.units,
        onStartDriving: widget.drivingController == null ? null : _startDriving,
        onEndShift: widget.drivingController == null ? null : _endShift,
        onPauseDriving: widget.drivingController == null ? null : _pauseDriving,
        onResumeDriving: widget.drivingController == null
            ? null
            : _resumeDriving,
        onAutoEndShift: widget.drivingController == null ? null : _autoEndShift,
        onCancelDriving: widget.drivingController == null
            ? null
            : _cancelDriving,
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
        units: widget.units,
        drivingCosts: widget.drivingCosts,
        clock: widget.clock,
        onAddShift: () => _addShift(returnToToday: false),
        onShiftUpdated: widget.onShiftUpdated,
        onShiftDeleted: widget.onShiftDeleted,
      ),
      2 => CoachScreen(shifts: widget.shifts, preferences: _preferences),
      3 => TaxYearScreen(
        shifts: widget.shifts,
        expenses: widget.expenses,
        units: widget.units,
        clock: widget.clock,
        receipts: widget.receiptStore,
        onExpenseAdded: widget.onExpenseAdded,
        onExpenseUpdated: widget.onExpenseUpdated,
        onExpenseDeleted: widget.onExpenseDeleted,
      ),
      _ => SettingsScreen(
        driverName: widget.driverName,
        shifts: widget.shifts,
        expenses: widget.expenses,
        onOpenTaxes: () => setState(() => _index = 3),
        dailyGoal: widget.dailyGoal,
        drivingCosts: widget.drivingCosts,
        hourlyFloor: widget.hourlyFloor,
        weekStartsOn: widget.weekStartsOn,
        drivingDaysPerWeek: widget.drivingDaysPerWeek,
        units: widget.units,
        onDriverNameChanged: widget.onDriverNameChanged,
        onDailyGoalChanged: widget.onDailyGoalChanged,
        onVehicleCostPerMileChanged: widget.onVehicleCostPerMileChanged,
        onEnergySourceChanged: widget.onEnergySourceChanged,
        onFuelEfficiencyChanged: widget.onFuelEfficiencyChanged,
        onFuelPriceChanged: widget.onFuelPriceChanged,
        onHourlyFloorChanged: widget.onHourlyFloorChanged,
        onWeekStartsOnChanged: widget.onWeekStartsOnChanged,
        onDrivingDaysPerWeekChanged: widget.onDrivingDaysPerWeekChanged,
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
                          child: BrandMark(size: 42),
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
            'can change this any time during the session.',
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
            'Keeprate needs location access to track your miles. You can '
                'still enter a session by hand.',
          StartFailure.permissionDeniedForever =>
            'Location is blocked for Keeprate. Only Settings can undo it.',
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
        const SnackBar(content: Text('Tracking the full session now.')),
      );
      return;
    }
    // The OS may decline to re-prompt at all, in which case Settings is the
    // only route and saying so beats silently doing nothing.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Set location to “Always” for Keeprate to keep counting miles '
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
              'Session ended automatically after '
              '${pauseAutoEndAfter.inHours} hours paused. Add your earnings '
              'when you are ready.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }),
    );
  }

  /// Throws the running session away without banking a shift.
  ///
  /// For the shift that should never have been recorded — the tracker left
  /// running on the drive home, a session started by accident. Confirmed like
  /// the draft discard, and for the same reason: it destroys tracked driving,
  /// and it is the only control on the live card that cannot be undone.
  Future<void> _cancelDriving() async {
    final controller = widget.drivingController;
    final session = controller?.session;
    if (controller == null || session == null) return;

    final elapsed = session.elapsed();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this session?'),
        content: Text(
          '${Money.hours(elapsed.inMinutes / 60)} and '
          '${_preferences.units.distanceLabel(session.miles)} have been '
          'tracked. Cancelling '
          'throws them away — nothing is saved to Today.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep driving'),
          ),
          FilledButton(
            key: const ValueKey('confirm-cancel-session'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.discard();
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
          drivingCosts: widget.drivingCosts,
          units: widget.units,
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
          'Your sessions and goals stay on your account and come back when you '
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
        title: const Text('Discard tracked session?'),
        content: Text(
          '${Money.hours(draft.hours)} and '
          '${_preferences.units.distanceLabel(draft.miles)} were tracked. '
          'Discarding this cannot be undone.',
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
          units: widget.units,
          drivingCosts: widget.drivingCosts,
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
          drivingCosts: widget.drivingCosts,
          units: widget.units,
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

  /// The whole history — every session and every standalone expense.
  ///
  /// The Taxes tab exports the same file scoped to one year; this is the
  /// personal-backup end of the same feature, so it deliberately takes no year.
  Future<void> _exportData() async {
    final exported = await HistoryExport(
      units: widget.units,
    ).share(widget.shifts, expenses: widget.expenses);
    if (!mounted || exported) return;
    // A driver with only expenses logged still has something to export, so the
    // refusal is about having no records at all, not about having no sessions.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add a session or an expense before exporting data.'),
      ),
    );
  }

  Future<void> _openPrivacy() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PrivacySecurityScreen(
        accountEmail: widget.accountEmail,
        onDeleteAccount: widget.onDeleteAccount,
      ),
    ),
  );
}
