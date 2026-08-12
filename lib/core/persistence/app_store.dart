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

  Map<String, Object?> toJson() => {
    'driverName': driverName,
    'dailyGoal': dailyGoal,
    'vehicleCostPerMile': vehicleCostPerMile,
    'shifts': shifts.map((shift) => shift.toJson()).toList(),
    'freedomGoal': freedomGoal?.toJson(),
    'themeMode': themeMode.name,
    'activeSession': activeSession?.toJson(),
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
    );
  }
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
