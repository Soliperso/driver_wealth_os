import 'package:flutter/material.dart' show ThemeMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/accounts/domain/work_platform.dart';
import '../../features/settings/domain/distance_unit.dart';
import '../../features/settings/domain/driving_costs.dart';
import '../../features/shifts/domain/shift.dart';
import '../persistence/app_store.dart';

/// Moves a driver's records between this device and their account.
///
/// **Local-first, deliberately.** Drivers work in parking garages, airport
/// holding lots and dead zones; the app has to stay fully usable with no
/// network, so the device keeps the working copy and this only reconciles.
/// Nothing in the UI ever waits on a round trip.
///
/// **Conflict rule: last writer wins, per record.** Two phones editing the same
/// shift is vanishingly rare — a driver has one — so the cost of being wrong is
/// low and the cost of a merge UI is high. A locally edited record always beats
/// an incoming one, because the driver is looking at the local one.
abstract interface class SyncService {
  Future<AppSnapshot> sync(AppSnapshot local);
}

/// Used when there is no backend or nobody is signed in. Hands the snapshot
/// straight back so every caller can be written as though sync always exists.
final class InertSyncService implements SyncService {
  const InertSyncService();

  @override
  Future<AppSnapshot> sync(AppSnapshot local) async => local;
}

final class SupabaseSyncService implements SyncService {
  SupabaseSyncService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// PostgREST caps a single response, so pulls are paged explicitly rather
  /// than trusting one unbounded select to return everything.
  static const _pageSize = 500;

  @override
  Future<AppSnapshot> sync(AppSnapshot local) async {
    final userId = _client.auth.currentSession?.user.id;
    // Not signed in: nothing to sync to, and the local copy stays untouched.
    if (userId == null) return local;

    // Read the server clock *before* pulling. Taking it afterwards would open a
    // window where a write that landed mid-pull is never seen again, because
    // the cursor would already be past it.
    final startedAt = await _serverNow();

    var merged = await _pull(local, userId);
    merged = await _push(merged, userId);

    return merged.copyWith(
      syncCursor: startedAt,
      dirtyShiftIds: const {},
      deletedShiftIds: const {},
      dirtyPreferences: false,
    );
  }

  Future<AppSnapshot> _pull(AppSnapshot local, String userId) async {
    final cursor = local.syncCursor;
    final rows = <Map<String, Object?>>[];

    var offset = 0;
    while (true) {
      var query = _client.from('shifts').select().eq('user_id', userId);
      if (cursor != null) {
        query = query.gt('updated_at', cursor.toUtc().toIso8601String());
      }
      final page = await query
          .order('updated_at')
          .range(offset, offset + _pageSize - 1);
      rows.addAll(page.map(Map<String, Object?>.from));
      if (page.length < _pageSize) break;
      offset += _pageSize;
    }

    return mergePulledShifts(local, rows);
  }

  Future<AppSnapshot> _push(AppSnapshot local, String userId) async {
    final dirty = local.shifts
        .where((shift) => local.dirtyShiftIds.contains(shift.id))
        .toList();

    if (dirty.isNotEmpty) {
      // Chunked: a driver with years of history would otherwise produce a
      // single multi-megabyte request that PostgREST rejects on body size.
      for (var start = 0; start < dirty.length; start += _pageSize) {
        final chunk = dirty.skip(start).take(_pageSize);
        await _client.from('shifts').upsert([
          for (final shift in chunk) _toRow(shift, userId),
        ], onConflict: 'user_id,id');
      }
    }

    if (local.deletedShiftIds.isNotEmpty) {
      // Soft delete. A hard delete would be undone by the next pull from a
      // device that still holds the row.
      final deletedAt = DateTime.now().toUtc().toIso8601String();
      await _client.from('shifts').upsert([
        for (final id in local.deletedShiftIds)
          {
            'user_id': userId,
            'id': id,
            'platform': WorkPlatform.other.id,
            'completed_at': deletedAt,
            'deleted_at': deletedAt,
          },
      ], onConflict: 'user_id,id');
    }

    if (local.dirtyPreferences) {
      await _client.from('driver_preferences').upsert({
        'user_id': userId,
        'driver_name': local.driverName,
        'daily_goal': local.dailyGoal,
        'vehicle_cost_per_mile': local.vehicleCostPerMile,
        'energy_source': local.energySource.name,
        'fuel_efficiency': local.fuelEfficiency,
        'fuel_price': local.fuelPrice,
        'hourly_floor': local.hourlyFloor,
        'week_starts_on': local.weekStartsOn,
        'driving_days_per_week': local.drivingDaysPerWeek,
        'distance_unit': local.distanceUnit.name,
        'theme_mode': local.themeMode.name,
      }, onConflict: 'user_id');
    }

    return local;
  }

  /// The server's clock, not the phone's.
  ///
  /// A device clock that is even slightly fast would advance the cursor past
  /// writes it has not seen, and those records would never be pulled again.
  Future<DateTime> _serverNow() async {
    final rows = await _client
        .from('shifts')
        .select('updated_at')
        .order('updated_at', ascending: false)
        .limit(1);
    // Falling back to the local clock is safe in the only case it happens —
    // an empty table, where there is nothing to miss.
    if (rows.isEmpty) return DateTime.now().toUtc();
    final latest = DateTime.tryParse(
      Map<String, Object?>.from(rows.first)['updated_at'] as String? ?? '',
    );
    return latest?.toUtc() ?? DateTime.now().toUtc();
  }

  static Map<String, Object?> _toRow(Shift shift, String userId) => {
    'user_id': userId,
    'id': shift.id,
    // The dominant app and the shift's whole gross. Both columns predate
    // multi-apping and are still written so a device on an older build reads a
    // lossy but honest version of the shift rather than nothing at all.
    'platform': shift.platform.id,
    'gross': shift.gross,
    'earnings': Shift.earningsToJson(shift.earnings),
    'hours': shift.hours,
    'miles': shift.miles,
    'direct_expenses': shift.directExpenses,
    'vehicle_cost_per_mile': shift.vehicleCostPerMile,
    'completed_at': shift.completedAt.toUtc().toIso8601String(),
    'source': shift.source.id,
    // Without this the flag resets to true on the next pull, quietly marking an
    // imported shift as cost-reviewed when the driver has not touched it.
    'costs_reviewed': shift.costsReviewed,
    // Explicitly cleared: re-saving a shift that was deleted elsewhere is an
    // undelete, not a no-op.
    'deleted_at': null,
  };

  /// Returns null rather than throwing for one malformed row. A single bad
  /// record must not abort a sync and strand every other change behind it.
  static Shift? rowToShift(Map<String, Object?> row) {
    final id = row['id'];
    final completedAt = DateTime.tryParse(row['completed_at'] as String? ?? '');
    if (id is! String || id.isEmpty || completedAt == null) return null;
    final source = ShiftSource.fromId(row['source']);
    return Shift(
      id: id,
      earnings: Shift.earningsFromJson(
        row['earnings'],
        legacyPlatform: row['platform'],
        // Rows written before the column existed, and rows from a project
        // whose migration has not run yet.
        legacyGross: () => _number(row['gross']),
        // Lenient on purpose: one unreadable earnings line must not throw out
        // of here and abort the sync, per this method's contract.
        parseAmount: _number,
      ),
      hours: _number(row['hours']),
      miles: _number(row['miles']),
      directExpenses: _number(row['direct_expenses']),
      vehicleCostPerMile: _number(row['vehicle_cost_per_mile']),
      completedAt: completedAt.toLocal(),
      source: source,
      // A row written before the column existed falls back to the same rule the
      // local decoder uses: only an import can arrive without the driver's own
      // fuel, toll and parking figures.
      costsReviewed: switch (row['costs_reviewed']) {
        final bool reviewed => reviewed,
        _ => source != ShiftSource.imported,
      },
    );
  }

  /// Postgres `numeric` arrives as a string over PostgREST, so a plain cast
  /// to num would drop every money value on the floor.
  static double _number(Object? value) {
    final parsed = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text) ?? 0,
      _ => 0.0,
    };
    return parsed.isFinite && parsed >= 0 ? parsed : 0;
  }
}

/// Folds rows pulled from the account into the device's copy.
///
/// Split out from the network code because this is where every decision that
/// can lose a driver's data lives, and it should be provable without a
/// backend. The rules, in order of precedence:
///
/// 1. A shift edited locally and not yet pushed always wins. The driver is
///    looking at that version; an incoming row is necessarily older.
/// 2. A shift deleted locally stays deleted, even if the server still has it.
/// 3. A row carrying `deleted_at` removes the shift here.
/// 4. Anything else overwrites, because it came from the driver's other device
///    and is newer than what this one holds.
AppSnapshot mergePulledShifts(
  AppSnapshot local,
  List<Map<String, Object?>> rows,
) {
  if (rows.isEmpty) return local;

  final byId = {for (final shift in local.shifts) shift.id: shift};
  var changed = false;

  for (final row in rows) {
    final id = row['id'];
    if (id is! String || id.isEmpty) continue;
    if (local.dirtyShiftIds.contains(id)) continue;
    if (local.deletedShiftIds.contains(id)) continue;

    if (row['deleted_at'] != null) {
      changed = byId.remove(id) != null || changed;
      continue;
    }
    final shift = SupabaseSyncService.rowToShift(row);
    // One malformed row must not abort the whole sync and strand every other
    // change behind it.
    if (shift == null) continue;
    byId[shift.id] = shift;
    changed = true;
  }

  if (!changed) return local;
  final shifts = byId.values.toList()
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  return local.copyWith(shifts: shifts);
}

/// Reads the driver's account-level settings and goal back onto a fresh device.
///
/// Separate from [SyncService.sync] because it only has to run when the local
/// snapshot has nothing of its own — a reinstall or a new phone. Merging these
/// on every sync would let a stale server copy overwrite a change the driver
/// just made.
extension RestoreAccountRecords on SupabaseSyncService {
  Future<AppSnapshot> restoreInto(AppSnapshot local) async {
    final userId = _client.auth.currentSession?.user.id;
    if (userId == null) return local;

    var restored = local;

    final preferences = await _client
        .from('driver_preferences')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (preferences != null) {
      final row = Map<String, Object?>.from(preferences);
      final name = row['driver_name'];
      double preferenceNumber(
        String key,
        double fallback, {
        required double min,
        required double max,
      }) {
        if (!row.containsKey(key)) return fallback;
        final value = SupabaseSyncService._number(row[key]);
        return value >= min && value <= max ? value : fallback;
      }

      restored = restored.copyWith(
        driverName: name is String && name.trim().isNotEmpty
            ? name.trim()
            : null,
        dailyGoal: preferenceNumber(
          'daily_goal',
          restored.dailyGoal,
          min: 1,
          max: 100000,
        ),
        vehicleCostPerMile: preferenceNumber(
          'vehicle_cost_per_mile',
          restored.vehicleCostPerMile,
          min: 0,
          max: 100,
        ),
        energySource: EnergySource.fromName(row['energy_source']),
        fuelEfficiency: preferenceNumber(
          'fuel_efficiency',
          restored.fuelEfficiency,
          min: .1,
          max: 500,
        ),
        fuelPrice: preferenceNumber(
          'fuel_price',
          restored.fuelPrice,
          min: 0,
          max: 100,
        ),
        hourlyFloor: preferenceNumber(
          'hourly_floor',
          restored.hourlyFloor,
          min: 1,
          max: 10000,
        ),
        weekStartsOn: row['week_starts_on'] == DateTime.sunday
            ? DateTime.sunday
            : DateTime.monday,
        drivingDaysPerWeek: switch (row['driving_days_per_week']) {
          final int days when days >= 1 && days <= 7 => days,
          _ => restored.drivingDaysPerWeek,
        },
        distanceUnit: DistanceUnit.fromName(row['distance_unit']),
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == row['theme_mode'],
          orElse: () => restored.themeMode,
        ),
      );
    }

    return restored;
  }
}
