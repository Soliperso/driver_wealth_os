import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/driving/domain/driving_session.dart';
import '../../features/settings/domain/driving_costs.dart';
import '../../features/settings/domain/distance_unit.dart';
import '../../features/shifts/domain/shift.dart';
import '../../features/freedom/domain/freedom_goal.dart';

class AppSnapshot {
  const AppSnapshot({
    this.driverName,
    this.dailyGoal = 250,
    this.vehicleCostPerMile = defaultVehicleCostPerMile,
    this.energySource = EnergySource.gasoline,
    this.fuelEfficiency = DrivingCosts.defaultFuelEfficiency,
    this.fuelPrice = DrivingCosts.defaultFuelPrice,
    this.hourlyFloor = defaultHourlyFloor,
    this.weekStartsOn = DateTime.monday,
    this.drivingDaysPerWeek = defaultDrivingDaysPerWeek,
    this.distanceUnit = DistanceUnit.miles,
    this.shifts = const [],
    this.freedomGoal,
    this.themeMode = ThemeMode.system,
    this.activeSession,
    this.pendingDraft,
    this.syncCursor,
    this.dirtyShiftIds = const {},
    this.deletedShiftIds = const {},
    this.dirtyPreferences = false,
    this.dirtyGoal = false,
  });

  /// Rough national average for maintenance, tyres and depreciation. Used until
  /// the driver sets their own rate, and applied to imported shifts, which
  /// arrive with no cost data of any kind.
  static const defaultVehicleCostPerMile =
      DrivingCosts.defaultVehicleCostPerMile;

  /// The pace the app used to call "healthy" for everyone. Keeping it as the
  /// default means an existing driver who never opens the new field sees no
  /// change in what Today and Coach tell them.
  static const defaultHourlyFloor = 25.0;

  static const defaultDrivingDaysPerWeek = 5;

  final String? driverName;
  final double dailyGoal;
  final double vehicleCostPerMile;
  final EnergySource energySource;
  final double fuelEfficiency;
  final double fuelPrice;

  /// The lowest hourly profit this driver considers worth the trip. Replaces a
  /// hardcoded $25 that was the app's opinion rather than theirs.
  final double hourlyFloor;

  /// [DateTime.monday] or [DateTime.sunday] — pay weeks differ by platform, and
  /// a chart that splits the driver's week in half is worse than no chart.
  final int weekStartsOn;

  final int drivingDaysPerWeek;
  final DistanceUnit distanceUnit;
  final List<Shift> shifts;
  final FreedomGoal? freedomGoal;
  final ThemeMode themeMode;

  /// The cost side of the preferences, bundled for the callers that price a
  /// mile rather than edit one.
  DrivingCosts get drivingCosts => DrivingCosts(
    energySource: energySource,
    fuelEfficiency: fuelEfficiency,
    fuelPrice: fuelPrice,
    vehicleCostPerMile: vehicleCostPerMile,
  );

  /// What a full working week at [dailyGoal] comes to.
  double get weeklyGoal => (dailyGoal * drivingDaysPerWeek * 100).round() / 100;

  /// A driving session that was still running when the app was last alive.
  /// Persisted so an OS kill mid-shift cannot lose the start time.
  final DrivingSession? activeSession;

  /// A finished session whose earnings have not been entered yet.
  ///
  /// Tracked hours and miles are unrecoverable once discarded — the driving is
  /// already done and cannot be replayed. So the draft outlives the earnings
  /// screen: backing out, or the OS killing the app on that screen, leaves it
  /// here to be resumed rather than throwing the shift away.
  final Shift? pendingDraft;

  // ---------------------------------------------------------------------------
  // Sync bookkeeping.
  //
  // The device is the working copy: a driver in a parking garage has to be able
  // to log a shift, and the app has to be able to tell later which of its
  // records the server has not seen. That is all this metadata is for.
  // ---------------------------------------------------------------------------

  /// Server clock at the last successful pull. Everything changed after it is
  /// what the next pull asks for.
  final DateTime? syncCursor;

  /// Shifts edited on this device and not yet accepted by the server.
  final Set<String> dirtyShiftIds;

  /// Tombstones. A deleted shift has to stay known until the delete is pushed,
  /// or the next pull from another device would resurrect it.
  final Set<String> deletedShiftIds;

  final bool dirtyPreferences;
  final bool dirtyGoal;

  bool get hasUnsyncedChanges =>
      dirtyShiftIds.isNotEmpty ||
      deletedShiftIds.isNotEmpty ||
      dirtyPreferences ||
      dirtyGoal;

  AppSnapshot copyWith({
    List<Shift>? shifts,
    FreedomGoal? freedomGoal,
    bool clearFreedomGoal = false,
    String? driverName,
    double? dailyGoal,
    double? vehicleCostPerMile,
    EnergySource? energySource,
    double? fuelEfficiency,
    double? fuelPrice,
    double? hourlyFloor,
    int? weekStartsOn,
    int? drivingDaysPerWeek,
    DistanceUnit? distanceUnit,
    ThemeMode? themeMode,
    DateTime? syncCursor,
    Set<String>? dirtyShiftIds,
    Set<String>? deletedShiftIds,
    bool? dirtyPreferences,
    bool? dirtyGoal,
  }) => AppSnapshot(
    driverName: driverName ?? this.driverName,
    dailyGoal: dailyGoal ?? this.dailyGoal,
    vehicleCostPerMile: vehicleCostPerMile ?? this.vehicleCostPerMile,
    energySource: energySource ?? this.energySource,
    fuelEfficiency: fuelEfficiency ?? this.fuelEfficiency,
    fuelPrice: fuelPrice ?? this.fuelPrice,
    hourlyFloor: hourlyFloor ?? this.hourlyFloor,
    weekStartsOn: weekStartsOn ?? this.weekStartsOn,
    drivingDaysPerWeek: drivingDaysPerWeek ?? this.drivingDaysPerWeek,
    distanceUnit: distanceUnit ?? this.distanceUnit,
    shifts: shifts ?? this.shifts,
    freedomGoal: clearFreedomGoal ? null : (freedomGoal ?? this.freedomGoal),
    themeMode: themeMode ?? this.themeMode,
    activeSession: activeSession,
    pendingDraft: pendingDraft,
    syncCursor: syncCursor ?? this.syncCursor,
    dirtyShiftIds: dirtyShiftIds ?? this.dirtyShiftIds,
    deletedShiftIds: deletedShiftIds ?? this.deletedShiftIds,
    dirtyPreferences: dirtyPreferences ?? this.dirtyPreferences,
    dirtyGoal: dirtyGoal ?? this.dirtyGoal,
  );

  Map<String, Object?> toJson() => {
    'driverName': driverName,
    'dailyGoal': dailyGoal,
    'vehicleCostPerMile': vehicleCostPerMile,
    'energySource': energySource.name,
    'fuelEfficiency': fuelEfficiency,
    'fuelPrice': fuelPrice,
    'hourlyFloor': hourlyFloor,
    'weekStartsOn': weekStartsOn,
    'drivingDaysPerWeek': drivingDaysPerWeek,
    'distanceUnit': distanceUnit.name,
    'shifts': shifts.map((shift) => shift.toJson()).toList(),
    'freedomGoal': freedomGoal?.toJson(),
    'themeMode': themeMode.name,
    'activeSession': activeSession?.toJson(),
    'pendingDraft': pendingDraft?.toJson(),
    'syncCursor': syncCursor?.toUtc().toIso8601String(),
    'dirtyShiftIds': dirtyShiftIds.toList(),
    'deletedShiftIds': deletedShiftIds.toList(),
    'dirtyPreferences': dirtyPreferences,
    'dirtyGoal': dirtyGoal,
  };

  factory AppSnapshot.fromJson(Map<String, Object?> json) {
    final rawShifts = json['shifts'];
    final uniqueShifts = <String, Shift>{};
    if (rawShifts is List) {
      for (final entry in rawShifts) {
        if (entry is! Map) continue;
        try {
          final shift = Shift.fromJson(Map<String, Object?>.from(entry));
          uniqueShifts.putIfAbsent(shift.id, () => shift);
        } on FormatException {
          // Ignore one damaged record without discarding the remaining history.
        }
      }
    }
    final rawDailyGoal = json['dailyGoal'];
    final goal = rawDailyGoal is num ? rawDailyGoal.toDouble() : 250.0;
    final rawVehicleRate = json['vehicleCostPerMile'];
    final vehicleRate = rawVehicleRate is num
        ? rawVehicleRate.toDouble()
        : defaultVehicleCostPerMile;
    final rawName = json['driverName'];
    Shift? pendingDraft;
    final rawPendingDraft = json['pendingDraft'];
    if (rawPendingDraft is Map) {
      try {
        pendingDraft = Shift.fromJson(
          Map<String, Object?>.from(rawPendingDraft),
        );
      } on FormatException {
        // A damaged draft is dropped; the saved history still loads.
        pendingDraft = null;
      }
    }
    FreedomGoal? freedomGoal;
    final rawFreedomGoal = json['freedomGoal'];
    if (rawFreedomGoal is Map) {
      try {
        freedomGoal = FreedomGoal.fromJson(
          Map<String, Object?>.from(rawFreedomGoal),
        );
      } on FormatException {
        freedomGoal = null;
      }
    }
    return AppSnapshot(
      driverName: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : null,
      dailyGoal: goal > 0 && goal <= 100000 ? goal : 250,
      vehicleCostPerMile: vehicleRate >= 0 && vehicleRate <= 100
          ? vehicleRate
          : defaultVehicleCostPerMile,
      energySource: EnergySource.fromName(json['energySource']),
      fuelEfficiency: _boundedDouble(
        json['fuelEfficiency'],
        fallback: DrivingCosts.defaultFuelEfficiency,
        min: 0,
        max: 500,
        allowMin: false,
      ),
      fuelPrice: _boundedDouble(
        json['fuelPrice'],
        fallback: DrivingCosts.defaultFuelPrice,
        min: 0,
        max: 100,
      ),
      hourlyFloor: _boundedDouble(
        json['hourlyFloor'],
        fallback: defaultHourlyFloor,
        min: 0,
        max: 10000,
      ),
      // Anything but Monday or Sunday would silently rotate every weekly chart
      // in the app, so an unknown value falls back rather than being clamped.
      weekStartsOn: switch (json['weekStartsOn']) {
        DateTime.sunday => DateTime.sunday,
        _ => DateTime.monday,
      },
      drivingDaysPerWeek: switch (json['drivingDaysPerWeek']) {
        final int days when days >= 1 && days <= 7 => days,
        _ => defaultDrivingDaysPerWeek,
      },
      distanceUnit: DistanceUnit.fromName(json['distanceUnit']),
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      activeSession: switch (json['activeSession']) {
        final Map<Object?, Object?> raw => DrivingSession.fromJson(
          Map<String, Object?>.from(raw),
        ),
        _ => null,
      },
      shifts: uniqueShifts.values.toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt)),
      freedomGoal: freedomGoal,
      pendingDraft: pendingDraft,
      syncCursor: DateTime.tryParse(json['syncCursor'] as String? ?? ''),
      // A snapshot written before sync existed has no bookkeeping. Treating
      // its records as clean would strand them on the device forever, so the
      // first sign-in uploads everything instead — see SyncService.
      dirtyShiftIds: _stringSet(json['dirtyShiftIds']),
      deletedShiftIds: _stringSet(json['deletedShiftIds']),
      dirtyPreferences: json['dirtyPreferences'] == true,
      dirtyGoal: json['dirtyGoal'] == true,
    );
  }

  /// A stored number that has drifted outside what the UI can produce — a
  /// hand-edited backup, a future version's wider range — falls back to the
  /// default rather than being clamped into a value the driver never chose.
  static double _boundedDouble(
    Object? value, {
    required double fallback,
    required double min,
    required double max,
    bool allowMin = true,
  }) {
    if (value is! num) return fallback;
    final parsed = value.toDouble();
    if (!parsed.isFinite) return fallback;
    if (parsed > max) return fallback;
    if (allowMin ? parsed < min : parsed <= min) return fallback;
    return parsed;
  }

  static Set<String> _stringSet(Object? value) => switch (value) {
    final List<Object?> raw => {
      for (final entry in raw)
        if (entry is String && entry.isNotEmpty) entry,
    },
    _ => const {},
  };
}

abstract interface class AppStore {
  Future<AppSnapshot> load();

  Future<void> save(AppSnapshot snapshot);
}

final class SharedPreferencesAppStore implements AppStore {
  SharedPreferencesAppStore({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _snapshotKey = 'driver_wealth_app_snapshot_v1';
  final Future<SharedPreferences> _preferences;

  @override
  Future<AppSnapshot> load() async {
    final preferences = await _preferences;
    final encoded = preferences.getString(_snapshotKey);
    if (encoded == null) return const AppSnapshot();
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const AppSnapshot();
      return AppSnapshot.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const AppSnapshot();
    }
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    final preferences = await _preferences;
    await preferences.setString(_snapshotKey, jsonEncode(snapshot.toJson()));
  }
}

final class MemoryAppStore implements AppStore {
  MemoryAppStore([this.snapshot = const AppSnapshot()]);

  AppSnapshot snapshot;

  @override
  Future<AppSnapshot> load() async => snapshot;

  @override
  Future<void> save(AppSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}
