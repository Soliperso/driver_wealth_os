import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shifts/domain/shift.dart';
import '../domain/work_platform.dart';

/// Reads earnings that the backend has already imported and normalised.
///
/// The sync itself runs server side; this is the return path that brings those
/// figures back into the app, which is what makes a connected account visible
/// anywhere other than the connection screen.
abstract interface class EarningsRepository {
  Future<List<Shift>> fetchImportedShifts({required double vehicleCostPerMile});

  Future<SyncStatus?> latestSync();
}

enum SyncState { running, succeeded, failed }

class SyncStatus {
  const SyncStatus({
    required this.state,
    required this.startedAt,
    this.finishedAt,
    this.recordsProcessed = 0,
    this.errorMessage,
  });

  final SyncState state;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int recordsProcessed;
  final String? errorMessage;

  static SyncStatus? fromRow(Map<String, Object?> row) {
    final startedAt = DateTime.tryParse(row['started_at'] as String? ?? '');
    if (startedAt == null) return null;
    return SyncStatus(
      state: switch (row['status']) {
        'succeeded' => SyncState.succeeded,
        'failed' => SyncState.failed,
        _ => SyncState.running,
      },
      startedAt: startedAt.toLocal(),
      finishedAt: DateTime.tryParse(
        row['finished_at'] as String? ?? '',
      )?.toLocal(),
      recordsProcessed: switch (row['records_processed']) {
        final int value => value,
        final num value => value.toInt(),
        _ => 0,
      },
      errorMessage: row['error_message'] as String?,
    );
  }
}

/// Used when the backend is not configured. Reports no imported earnings
/// instead of pretending a sync happened.
final class InertEarningsRepository implements EarningsRepository {
  const InertEarningsRepository();

  @override
  Future<List<Shift>> fetchImportedShifts({
    required double vehicleCostPerMile,
  }) async => const [];

  @override
  Future<SyncStatus?> latestSync() async => null;
}

final class SupabaseEarningsRepository implements EarningsRepository {
  const SupabaseEarningsRepository();

  /// PostgREST caps a single response, so pages are requested explicitly and
  /// drained until one comes back short. Relying on a single unbounded select
  /// would silently drop a long history and under-report profit.
  static const _pageSize = 500;
  static const _maxPages = 200;

  @override
  Future<List<Shift>> fetchImportedShifts({
    required double vehicleCostPerMile,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return const [];

    final rows = <Map<String, Object?>>[];
    for (var page = 0; page < _maxPages; page++) {
      final offset = page * _pageSize;
      final response = await client
          .rpc('imported_shift_days', params: {'tz_name': _localTimeZoneName()})
          .range(offset, offset + _pageSize - 1);
      if (response is! List) break;
      rows.addAll(response.whereType<Map>().map(Map<String, Object?>.from));
      if (response.length < _pageSize) break;
    }

    return rows
        .map((row) => _toShift(row, vehicleCostPerMile))
        .nonNulls
        .toList();
  }

  @override
  Future<SyncStatus?> latestSync() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return null;
    final row = await client
        .from('sync_jobs')
        .select(
          'status, records_processed, error_message, started_at, '
          'finished_at',
        )
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return SyncStatus.fromRow(Map<String, Object?>.from(row));
  }

  static Shift? _toShift(Map<String, Object?> row, double vehicleCostPerMile) {
    final day = DateTime.tryParse(row['local_day'] as String? ?? '');
    if (day == null) return null;
    final platform = WorkPlatform.values.firstWhere(
      (candidate) => candidate.id == row['platform'],
      orElse: () => WorkPlatform.other,
    );

    // Timestamps arrive as UTC; the local wall-clock time is what decides
    // which day-and-time pattern the shift is graded under.
    final lastActivity = DateTime.tryParse(
      row['last_activity_at'] as String? ?? '',
    )?.toLocal();
    final completedAt =
        lastActivity ?? DateTime(day.year, day.month, day.day, 23, 59);

    return Shift(
      id: importedShiftId(platform, day),
      platform: platform,
      gross: _positive(row['gross']),
      hours: _positive(row['hours']),
      miles: _positive(row['miles']),
      // A gig feed reports what the platform paid, never what the driver spent
      // on fuel, tolls or parking. Those stay zero until the driver adds them.
      directExpenses: 0,
      vehicleCostPerMile: vehicleCostPerMile,
      completedAt: completedAt,
      source: ShiftSource.imported,
    );
  }

  /// Nulls are expected: a platform may report earnings without a duration or
  /// distance. Shift rejects null and non-finite values, so they are coerced
  /// here rather than dropping the whole day's earnings.
  static double _positive(Object? value) {
    final parsed = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text) ?? 0,
      _ => 0.0,
    };
    return parsed.isFinite && parsed > 0 ? parsed : 0;
  }

  static String _localTimeZoneName() {
    // Falls back to a fixed UTC offset when the platform gives no IANA name;
    // Postgres accepts both forms.
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }
}

/// Stable across syncs so re-importing the same day replaces its shift instead
/// of adding a duplicate. The `manual-` prefix used for hand-entered shifts
/// cannot collide with this.
String importedShiftId(WorkPlatform platform, DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final dayOfMonth = day.day.toString().padLeft(2, '0');
  return 'imported:${platform.id}:${day.year}-$month-$dayOfMonth';
}
