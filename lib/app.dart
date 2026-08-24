import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/backend_config.dart';
import 'core/persistence/app_store.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/accounts/application/earnings_repository.dart';
import 'features/admin/application/admin_repository.dart';
import 'features/auth/application/auth_gateway.dart';
import 'features/auth/domain/auth_user.dart';
import 'features/auth/presentation/sign_in_screen.dart';
import 'features/driving/application/driving_session_controller.dart';
import 'features/driving/application/location_tracker.dart';
import 'features/driving/domain/driving_session.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/shifts/domain/shift.dart';
import 'features/settings/domain/driving_costs.dart';
import 'features/settings/domain/distance_unit.dart';
import 'features/today/presentation/app_shell.dart';

class DriverWealthApp extends StatefulWidget {
  const DriverWealthApp({
    super.key,
    this.store,
    this.earningsRepository,
    this.locationTracker,
    this.drivingRefreshInterval = const Duration(seconds: 1),
    this.clock,
    this.authGateway,
    this.syncService,
    this.adminRepository,
  });

  /// Injectable so the sync rules can be tested without a backend.
  final SyncService? syncService;

  final AppStore? store;

  /// Null means this build has no backend, so there is nothing to sign in to
  /// and the app runs entirely on device. Injectable so tests can drive the
  /// signed-in and signed-out paths without a network.
  final AuthGateway? authGateway;

  /// Injectable so owner access and dashboard behavior can be tested without
  /// granting test accounts any backend privileges.
  final AdminRepository? adminRepository;

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
  EnergySource _energySource = EnergySource.gasoline;
  double _fuelEfficiency = DrivingCosts.defaultFuelEfficiency;
  double _fuelPrice = DrivingCosts.defaultFuelPrice;
  double _hourlyFloor = AppSnapshot.defaultHourlyFloor;
  int _weekStartsOn = DateTime.monday;
  int _drivingDaysPerWeek = AppSnapshot.defaultDrivingDaysPerWeek;
  DistanceUnit _distanceUnit = DistanceUnit.miles;
  ThemeMode _themeMode = ThemeMode.system;
  DrivingSession? _activeSession;
  Shift? _pendingDraft;
  Future<void> _pendingSave = Future.value();

  AuthGateway? _auth;
  AuthUser? _user;
  StreamSubscription<AuthUser?>? _authChanges;
  AdminRepository? _admin;
  var _adminAccess = false;

  late final SyncService _sync;
  DateTime? _syncCursor;
  final Set<String> _dirtyShiftIds = {};
  final Set<String> _deletedShiftIds = {};
  var _dirtyPreferences = false;
  var _syncingRecords = false;

  /// Surfaced in the UI rather than swallowed: a driver whose shifts have
  /// silently stopped persisting must find out from the app, not from a gap in
  /// their history weeks later.
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? MemoryAppStore();
    // Only a configured build has anything to sign in to. Without a backend
    // the app is local-only, and demanding an account for storage that never
    // leaves the device would be theatre.
    _auth =
        widget.authGateway ??
        (BackendConfig.isConfigured ? SupabaseAuthGateway() : null);
    _admin =
        widget.adminRepository ??
        (BackendConfig.isConfigured ? SupabaseAdminRepository() : null);
    _user = _auth?.currentUser;
    _sync =
        widget.syncService ??
        (BackendConfig.isConfigured
            ? SupabaseSyncService()
            : const InertSyncService());
    _authChanges = _auth?.changes.listen((user) {
      if (!mounted) return;
      final signedIn = _user == null && user != null;
      setState(() {
        _user = user;
        if (user == null) _adminAccess = false;
      });
      if (user != null) unawaited(_refreshAdminAccess());
      // Signing in is the moment a device's records acquire an owner. Anything
      // already here was entered before there was an account to attach it to,
      // so it is pushed rather than left stranded.
      if (signedIn) unawaited(_syncRecords(uploadEverything: true));
    });
    _earnings =
        widget.earningsRepository ??
        (BackendConfig.isConfigured && BackendConfig.incomeSyncEnabled
            ? const SupabaseEarningsRepository()
            : const InertEarningsRepository());
    if (_user != null) unawaited(_refreshAdminAccess());
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
      // A shift that ended itself has real hours and miles in it, and it can
      // end during start-up before any screen exists to catch it. Banking it
      // here means the only way to lose it is to discard it on purpose.
      // The guard matters: this can fire from the unawaited resume below,
      // which may land after the widget is gone.
      onAutoEnded: (draft) {
        if (mounted) _changePendingDraft(draft);
      },
    );
    unawaited(_driving!.resumeIfActive());
  }

  @override
  void dispose() {
    unawaited(_authChanges?.cancel());
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
          // Sign-in comes before onboarding: the name asked for there belongs
          // to an account, not to a device. A stored session is restored
          // without a network round trip, so this does not block offline use
          // once the driver has signed in.
          : (_auth != null && _user == null)
          ? SignInScreen(gateway: _auth!)
          : _driverName == null
          ? OnboardingScreen(onComplete: _completeOnboarding)
          : AppShell(
              driverName: _driverName!,
              shifts: _shifts,
              dailyGoal: _dailyGoal,
              vehicleCostPerMile: _vehicleCostPerMile,
              drivingCosts: _drivingCosts,
              hourlyFloor: _hourlyFloor,
              weekStartsOn: _weekStartsOn,
              drivingDaysPerWeek: _drivingDaysPerWeek,
              distanceUnit: _distanceUnit,
              onShiftAdded: _addShift,
              onShiftUpdated: _updateShift,
              onShiftDeleted: _deleteShift,
              onDailyGoalChanged: _changeDailyGoal,
              onVehicleCostPerMileChanged: _changeVehicleCostPerMile,
              onEnergySourceChanged: _changeEnergySource,
              onFuelEfficiencyChanged: _changeFuelEfficiency,
              onFuelPriceChanged: _changeFuelPrice,
              onHourlyFloorChanged: _changeHourlyFloor,
              onWeekStartsOnChanged: _changeWeekStartsOn,
              onDrivingDaysPerWeekChanged: _changeDrivingDaysPerWeek,
              onDistanceUnitChanged: _changeDistanceUnit,
              onDriverNameChanged: _changeDriverName,
              themeMode: _themeMode,
              onThemeModeChanged: _changeThemeMode,
              syncStatus: _syncStatus,
              onRefreshEarnings: refreshImportedEarnings,
              drivingController: _driving,
              drivingRefreshInterval: widget.drivingRefreshInterval,
              pendingDraft: _pendingDraft,
              onPendingDraftChanged: _changePendingDraft,
              storageError: _storageError,
              accountEmail: _user?.email,
              onSignOut: _auth == null ? null : _signOut,
              adminRepository: _adminAccess ? _admin : null,
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
      _energySource = snapshot.energySource;
      _fuelEfficiency = snapshot.fuelEfficiency;
      _fuelPrice = snapshot.fuelPrice;
      _hourlyFloor = snapshot.hourlyFloor;
      _weekStartsOn = snapshot.weekStartsOn;
      _drivingDaysPerWeek = snapshot.drivingDaysPerWeek;
      _distanceUnit = snapshot.distanceUnit;
      _themeMode = snapshot.themeMode;
      _activeSession = snapshot.activeSession;
      _pendingDraft = snapshot.pendingDraft;
      _syncCursor = snapshot.syncCursor;
      _dirtyShiftIds.addAll(snapshot.dirtyShiftIds);
      _deletedShiftIds.addAll(snapshot.deletedShiftIds);
      _dirtyPreferences = snapshot.dirtyPreferences;
      _shifts
        ..clear()
        ..addAll(snapshot.shifts);
      _loaded = true;
    });
    _createDrivingController();
    // A snapshot that predates sync has no cursor. Treat that first run as a
    // full upload so records entered before accounts existed are not stranded.
    await _syncRecords(uploadEverything: snapshot.syncCursor == null);
    await refreshImportedEarnings();
  }

  /// Reconciles this device's records with the driver's account.
  ///
  /// Never blocks the interface and never surfaces as an error the driver has
  /// to act on: the local copy is authoritative and complete on its own, so a
  /// failed sync means "not yet", not "something is broken".
  ///
  /// [uploadEverything] marks the whole device dirty. Used on first sign-in,
  /// where nothing has sync bookkeeping yet because it was all entered before
  /// there was an account.
  Future<void> _syncRecords({bool uploadEverything = false}) async {
    if (_user == null || _syncingRecords) return;
    _syncingRecords = true;
    try {
      if (uploadEverything) {
        _dirtyShiftIds.addAll(_shifts.map((shift) => shift.id));
        _dirtyPreferences = _dirtyPreferences || _driverName != null;
      }

      var snapshot = _snapshot();
      // A device with nothing of its own is a reinstall or a new phone, so the
      // account's name, goal and settings are pulled back down. Skipped
      // otherwise: a stale server copy must never overwrite live local edits.
      final sync = _sync;
      if (sync is SupabaseSyncService && _driverName == null) {
        snapshot = await sync.restoreInto(snapshot);
      }
      final merged = await sync.sync(snapshot);
      if (!mounted) return;
      _applySnapshot(merged);
    } catch (_) {
      // Deliberately quiet. Offline is the normal case for a driver, and the
      // dirty markers survive, so the next attempt picks up where this left
      // off. Storage failures — which do lose data — are reported separately.
    } finally {
      _syncingRecords = false;
    }
  }

  /// Adopts a synced snapshot as the new local state.
  void _applySnapshot(AppSnapshot snapshot) {
    setState(() {
      _driverName = snapshot.driverName;
      _dailyGoal = snapshot.dailyGoal;
      _vehicleCostPerMile = snapshot.vehicleCostPerMile;
      _energySource = snapshot.energySource;
      _fuelEfficiency = snapshot.fuelEfficiency;
      _fuelPrice = snapshot.fuelPrice;
      _hourlyFloor = snapshot.hourlyFloor;
      _weekStartsOn = snapshot.weekStartsOn;
      _drivingDaysPerWeek = snapshot.drivingDaysPerWeek;
      _distanceUnit = snapshot.distanceUnit;
      _themeMode = snapshot.themeMode;
      _syncCursor = snapshot.syncCursor;
      _shifts
        ..clear()
        ..addAll(snapshot.shifts);
      _dirtyShiftIds
        ..clear()
        ..addAll(snapshot.dirtyShiftIds);
      _deletedShiftIds
        ..clear()
        ..addAll(snapshot.deletedShiftIds);
      _dirtyPreferences = snapshot.dirtyPreferences;
    });
    _save();
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
    } catch (error) {
      // A backend that is unreachable or rejecting the session must not take
      // the app down with it: manual tracking works offline by design. The
      // failure is recorded so the sync card can say so.
      if (!mounted) return;
      setState(
        () => _syncStatus = SyncStatus.localFailure(
          'Could not reach your imported earnings.',
        ),
      );
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
          costsReviewed: existing.costsReviewed,
        );
      }
      _shifts.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      // Imported days are pushed too, so a second device sees them without
      // having to re-derive them from the earnings feed itself.
      _dirtyShiftIds.addAll(imported.map((shift) => shift.id));
    });
    _saveAndSync();
  }

  void _completeOnboarding(String name) {
    setState(() {
      _driverName = name.trim();
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _addShift(Shift shift) {
    if (_shifts.any((savedShift) => savedShift.id == shift.id)) {
      // Already saved — but a resumed draft still has to be cleared, or the
      // recovery card would offer it again forever.
      _changePendingDraft(null);
      return;
    }
    setState(() {
      _shifts.insert(0, shift);
      // Saving is what retires the draft. Anything else leaves it recoverable.
      _pendingDraft = null;
      _dirtyShiftIds.add(shift.id);
      // Re-adding an id that was deleted elsewhere is an undelete.
      _deletedShiftIds.remove(shift.id);
    });
    _saveAndSync();
  }

  /// Signs out and clears this device's copy of the driver's data.
  ///
  /// Leaving it behind would show the next person to sign in on this phone the
  /// previous driver's earnings. The data is not lost — it lives under the
  /// account and comes back on the next sign-in.
  Future<void> _signOut() async {
    // Flush first. Signing out wipes the device, so anything not yet pushed
    // would be destroyed rather than merely removed from here.
    if (_user != null) await _syncRecords();
    await _auth?.signOut();
    // Wait for the in-flight write chain before overwriting, or a queued save
    // of the old driver's state could land after the wipe.
    await _pendingSave;
    if (!mounted) return;
    setState(() {
      _driverName = null;
      _shifts.clear();
      _pendingDraft = null;
      _activeSession = null;
      _syncStatus = null;
      _dailyGoal = 250;
      _vehicleCostPerMile = AppSnapshot.defaultVehicleCostPerMile;
      _energySource = EnergySource.gasoline;
      _fuelEfficiency = DrivingCosts.defaultFuelEfficiency;
      _fuelPrice = DrivingCosts.defaultFuelPrice;
      _hourlyFloor = AppSnapshot.defaultHourlyFloor;
      _weekStartsOn = DateTime.monday;
      _drivingDaysPerWeek = AppSnapshot.defaultDrivingDaysPerWeek;
      _distanceUnit = DistanceUnit.miles;
      _themeMode = ThemeMode.system;
      // The next account to sign in here starts from a clean slate: a leftover
      // cursor would make its first pull skip everything already on the server.
      _syncCursor = null;
      _dirtyShiftIds.clear();
      _deletedShiftIds.clear();
      _dirtyPreferences = false;
      _adminAccess = false;
    });
    _save();
  }

  Future<void> _refreshAdminAccess() async {
    final repository = _admin;
    final expectedUserId = _user?.id;
    if (repository == null || expectedUserId == null) return;
    var allowed = false;
    try {
      allowed = await repository.canAccessAdmin();
    } catch (_) {
      // A missing migration or an offline backend must fail closed.
      allowed = false;
    }
    if (!mounted || _user?.id != expectedUserId) return;
    setState(() => _adminAccess = allowed);
  }

  void _changePendingDraft(Shift? draft) {
    if (_pendingDraft == null && draft == null) return;
    setState(() => _pendingDraft = draft);
    _save();
  }

  void _updateShift(Shift shift) {
    final index = _shifts.indexWhere((savedShift) => savedShift.id == shift.id);
    if (index == -1) return;
    setState(() {
      _shifts[index] = shift;
      _shifts.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      _dirtyShiftIds.add(shift.id);
    });
    _saveAndSync();
  }

  void _deleteShift(String shiftId) {
    final removed = _shifts.where((shift) => shift.id == shiftId).isNotEmpty;
    if (!removed) return;
    setState(() {
      _shifts.removeWhere((shift) => shift.id == shiftId);
      // A tombstone, not just a local removal. Without it the next pull from
      // another device would bring the shift straight back.
      _deletedShiftIds.add(shiftId);
      _dirtyShiftIds.remove(shiftId);
    });
    _saveAndSync();
  }

  void _changeDailyGoal(double goal) {
    setState(() {
      _dailyGoal = (goal * 100).round() / 100;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeVehicleCostPerMile(double rate) {
    setState(() {
      _vehicleCostPerMile = (rate * 10000).round() / 10000;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeEnergySource(EnergySource source) {
    setState(() {
      _energySource = source;
      // A gas MPG or per-gallon price is not meaningful for an EV (and vice
      // versa), so switching the energy source starts from a realistic value
      // for that source instead of silently reinterpreting the old number.
      _fuelEfficiency = source.defaultEfficiency;
      _fuelPrice = source.defaultPrice;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeFuelEfficiency(double efficiency) {
    setState(() {
      _fuelEfficiency = (efficiency * 100).round() / 100;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeFuelPrice(double price) {
    setState(() {
      _fuelPrice = (price * 1000).round() / 1000;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeHourlyFloor(double rate) {
    setState(() {
      _hourlyFloor = (rate * 100).round() / 100;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeWeekStartsOn(int weekday) {
    if (weekday != DateTime.monday && weekday != DateTime.sunday) return;
    setState(() {
      _weekStartsOn = weekday;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeDrivingDaysPerWeek(int days) {
    if (days < 1 || days > 7) return;
    setState(() {
      _drivingDaysPerWeek = days;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeDistanceUnit(DistanceUnit unit) {
    setState(() {
      _distanceUnit = unit;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  void _changeDriverName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _driverName = trimmed;
      _dirtyPreferences = true;
    });
    _saveAndSync();
  }

  AppSnapshot _snapshot() => AppSnapshot(
    driverName: _driverName,
    dailyGoal: _dailyGoal,
    vehicleCostPerMile: _vehicleCostPerMile,
    energySource: _energySource,
    fuelEfficiency: _fuelEfficiency,
    fuelPrice: _fuelPrice,
    hourlyFloor: _hourlyFloor,
    weekStartsOn: _weekStartsOn,
    drivingDaysPerWeek: _drivingDaysPerWeek,
    distanceUnit: _distanceUnit,
    themeMode: _themeMode,
    activeSession: _activeSession,
    shifts: List.unmodifiable(_shifts),
    pendingDraft: _pendingDraft,
    syncCursor: _syncCursor,
    dirtyShiftIds: Set.unmodifiable(_dirtyShiftIds),
    deletedShiftIds: Set.unmodifiable(_deletedShiftIds),
    dirtyPreferences: _dirtyPreferences,
  );

  DrivingCosts get _drivingCosts => DrivingCosts(
    energySource: _energySource,
    fuelEfficiency: _fuelEfficiency,
    fuelPrice: _fuelPrice,
    vehicleCostPerMile: _vehicleCostPerMile,
  );

  /// Writes to the device, then reconciles with the account in the background.
  ///
  /// The order matters and the second half is not awaited: the local write is
  /// what makes the change durable, and no interaction should wait on a
  /// network the driver may not have.
  void _saveAndSync() {
    _save();
    unawaited(_syncRecords());
  }

  void _save() {
    final snapshot = _snapshot();
    // Saves are serialised so a burst of edits cannot interleave and write an
    // older snapshot last. A failure is reported instead of vanishing into an
    // unhandled future, and the chain is reset so one bad write does not
    // poison every save that follows.
    _pendingSave = _pendingSave
        .then((_) => _store.save(snapshot))
        .then((_) {
          if (mounted && _storageError != null) {
            setState(() => _storageError = null);
          }
        })
        .catchError((Object error) {
          if (!mounted) return;
          setState(
            () => _storageError =
                'Your last change could not be saved to this device.',
          );
        });
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
