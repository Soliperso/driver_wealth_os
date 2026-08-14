import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/driving/domain/driving_session.dart';
import '../../features/shifts/domain/shift.dart';
import '../../features/freedom/domain/freedom_goal.dart';

class AppSnapshot {
  const AppSnapshot({
    this.driverName,
    this.dailyGoal = 250,
    this.vehicleCostPerMile = defaultVehicleCostPerMile,
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
  static const defaultVehicleCostPerMile = 0.30;

  final String? driverName;
  final double dailyGoal;
  final double vehicleCostPerMile;
  final List<Shift> shifts;
  final FreedomGoal? freedomGoal;
  final ThemeMode themeMode;

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
