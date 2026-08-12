import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/backend_config.dart';
import 'core/persistence/app_store.dart';
import 'core/theme/app_theme.dart';
import 'features/accounts/application/earnings_repository.dart';
import 'features/driving/application/driving_session_controller.dart';
import 'features/driving/application/location_tracker.dart';
import 'features/driving/domain/driving_session.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/freedom/domain/freedom_goal.dart';
import 'features/shifts/domain/shift.dart';
import 'features/today/presentation/app_shell.dart';

class DriverWealthApp extends StatefulWidget {
  const DriverWealthApp({
    super.key,
    this.store,
    this.earningsRepository,
    this.locationTracker,
    this.drivingRefreshInterval = const Duration(seconds: 1),
    this.clock,
  });

  final AppStore? store;

  /// Injectable so tests can supply imported earnings without a backend.
  final EarningsRepository? earningsRepository;

  /// Injectable so tests can drive a session without a device GPS.
  final LocationTracker? locationTracker;

  /// Null freezes the live session clock, which tests need so the widget tree
  /// can reach a settled frame.
  final Duration? drivingRefreshInterval;

  /// Injectable wall clock. `DateTime.now()` is not faked by the test binding,
  /// so without this a widget test can only ever produce a zero-length shift.
  final DateTime Function()? clock;

  @override
  State<DriverWealthApp> createState() => _DriverWealthAppState();
}

class _DriverWealthAppState extends State<DriverWealthApp> {
  late final AppStore _store;
  late final EarningsRepository _earnings;
  DrivingSessionController? _driving;
  var _loaded = false;
  SyncStatus? _syncStatus;
  var _syncing = false;
  String? _driverName;
  final List<Shift> _shifts = [];
  double _dailyGoal = 250;
  double _vehicleCostPerMile = AppSnapshot.defaultVehicleCostPerMile;
  ThemeMode _themeMode = ThemeMode.system;
  DrivingSession? _activeSession;
  FreedomGoal? _freedomGoal;
  Future<void> _pendingSave = Future.value();

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? MemoryAppStore();
    _earnings =
        widget.earningsRepository ??
        (BackendConfig.isConfigured && BackendConfig.incomeSyncEnabled
            ? const SupabaseEarningsRepository()
            : const InertEarningsRepository());
    if (widget.store == null) {
      _loaded = true;
      _createDrivingController();
    } else {
      unawaited(_load());
    }
  }

  /// Built after the snapshot is read so a session that was running when the
  /// app was last alive is handed straight back to the controller.
  void _createDrivingController() {
    _driving = DrivingSessionController(
      tracker: widget.locationTracker ?? GeolocatorLocationTracker(),
      restored: _activeSession,
      clock: widget.clock,
      persist: (session) async {
        _activeSession = session;
        _save();
      },
    );
    unawaited(_driving!.resumeIfActive());
  }

  @override
  void dispose() {
    _driving?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Wealth OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: !_loaded
          ? const _LoadingScreen()
          : _driverName == null
          ? OnboardingScreen(onComplete: _completeOnboarding)
          : AppShell(
              driverName: _driverName!,
              shifts: _shifts,
              dailyGoal: _dailyGoal,
              vehicleCostPerMile: _vehicleCostPerMile,
              freedomGoal: _freedomGoal,
              onShiftAdded: _addShift,
              onShiftUpdated: _updateShift,
              onShiftDeleted: _deleteShift,
              onDailyGoalChanged: _changeDailyGoal,
              onVehicleCostPerMileChanged: _changeVehicleCostPerMile,
              onDriverNameChanged: _changeDriverName,
              themeMode: _themeMode,
              onThemeModeChanged: _changeThemeMode,
              onFreedomGoalChanged: _changeFreedomGoal,
              syncStatus: _syncStatus,
              onRefreshEarnings: refreshImportedEarnings,
              drivingController: _driving,
              drivingRefreshInterval: widget.drivingRefreshInterval,
            ),
    );
  }

  Future<void> _load() async {
    final snapshot = await _store.load();
    if (!mounted) return;
    setState(() {
      _driverName = snapshot.driverName;
      _dailyGoal = snapshot.dailyGoal;
      _vehicleCostPerMile = snapshot.vehicleCostPerMile;
      _themeMode = snapshot.themeMode;
      _activeSession = snapshot.activeSession;
      _freedomGoal = snapshot.freedomGoal;
      _shifts
        ..clear()
        ..addAll(snapshot.shifts);
      _loaded = true;
    });
    _createDrivingController();
    await refreshImportedEarnings();
  }

  /// Pulls whatever the backend has already imported and folds it into the
  /// local history. Safe to call repeatedly: shifts are keyed by a stable
  /// platform-and-day id, so a re-sync replaces rather than duplicates.
  Future<void> refreshImportedEarnings() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final imported = await _earnings.fetchImportedShifts(
        vehicleCostPerMile: _vehicleCostPerMile,
      );
      final status = await _earnings.latestSync();
      if (!mounted) return;
      setState(() => _syncStatus = status);
      _mergeImportedShifts(imported);
    } finally {
      _syncing = false;
    }
  }

  void _mergeImportedShifts(List<Shift> imported) {
    if (imported.isEmpty) return;
    setState(() {
      for (final shift in imported) {
        final index = _shifts.indexWhere((saved) => saved.id == shift.id);
        if (index == -1) {
          _shifts.add(shift);
          continue;
        }
        // A gig feed never reports fuel, tolls or parking, so anything the
        // driver entered by hand must survive the next sync.
        final existing = _shifts[index];
        _shifts[index] = shift.copyWith(
          directExpenses: existing.directExpenses,
          vehicleCostPerMile: existing.vehicleCostPerMile,
        );
      }
      _shifts.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    });
    _save();
  }

  void _completeOnboarding(String name) {
    setState(() => _driverName = name.trim());
    _save();
  }

  void _addShift(Shift shift) {
    if (_shifts.any((savedShift) => savedShift.id == shift.id)) return;
    setState(() => _shifts.insert(0, shift));
    _save();
  }

  void _updateShift(Shift shift) {
    final index = _shifts.indexWhere((savedShift) => savedShift.id == shift.id);
    if (index == -1) return;
    setState(() {
      _shifts[index] = shift;
      _shifts.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    });
    _save();
  }

  void _deleteShift(String shiftId) {
    final removed = _shifts.where((shift) => shift.id == shiftId).isNotEmpty;
    if (!removed) return;
    setState(() => _shifts.removeWhere((shift) => shift.id == shiftId));
    _save();
  }

  void _changeDailyGoal(double goal) {
    setState(() => _dailyGoal = (goal * 100).round() / 100);
    _save();
  }

  void _changeVehicleCostPerMile(double rate) {
    setState(() => _vehicleCostPerMile = (rate * 10000).round() / 10000);
    _save();
  }

  void _changeThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _save();
  }

  void _changeDriverName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() => _driverName = trimmed);
    _save();
  }

  void _changeFreedomGoal(FreedomGoal? goal) {
    setState(() => _freedomGoal = goal);
    _save();
  }

  void _save() {
    final snapshot = AppSnapshot(
      driverName: _driverName,
      dailyGoal: _dailyGoal,
      vehicleCostPerMile: _vehicleCostPerMile,
      themeMode: _themeMode,
      activeSession: _activeSession,
      shifts: List.unmodifiable(_shifts),
      freedomGoal: _freedomGoal,
    );
    _pendingSave = _pendingSave.then((_) => _store.save(snapshot));
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
