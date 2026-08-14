import 'package:flutter_timezone/flutter_timezone.dart';
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

  /// A failure the app itself hit while fetching, as opposed to one the
  /// backend recorded in `sync_jobs`. Reported the same way so an unreachable
  /// backend looks like what it is rather than like "no earnings yet".
  SyncStatus.localFailure(String message)
    : state = SyncState.failed,
      startedAt = DateTime.now(),
      finishedAt = DateTime.now(),
      recordsProcessed = 0,
      errorMessage = message;

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

    // Resolved once: the zone cannot change mid-pull, and asking the platform
    // per page would make the pages disagree if it somehow did.
    final timeZone = await _localTimeZoneName();

    final rows = <Map<String, Object?>>[];
    for (var page = 0; page < _maxPages; page++) {
      final offset = page * _pageSize;
      final response = await client
          .rpc('imported_shift_days', params: {'tz_name': timeZone})
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
    // The provider string the backend aggregated by, which is not always a
    // platform the app has an icon for. The id is built from *this* rather than
    // from the mapped platform: two unrecognised providers on the same day both
    // map to `other`, and keying on that made the second silently overwrite the
    // first, understating the driver's gross for the day.
    final providerId = switch (row['platform']) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => WorkPlatform.other.id,
    };
    final platform = WorkPlatform.values.firstWhere(
      (candidate) => candidate.id == providerId,
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
      id: importedShiftId(providerId, day),
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

  /// The device's IANA zone name, e.g. `America/New_York`.
  ///
  /// This used to synthesise `UTC±HH:MM` from the current offset, which was
  /// wrong twice over:
  ///
  /// 1. **The sign inverted.** Postgres has no such zone name, so it falls back
  ///    to POSIX parsing — where a positive offset means *west* of Greenwich,
  ///    the opposite of ISO 8601. `UTC-05:00` resolved to UTC+5, putting a New
  ///    York driver's day boundary ten hours out. Verified directly:
  ///    `timezone('UTC-05:00', …)` and `timezone('America/New_York', …)`
  ///    return times ten hours apart.
  /// 2. **No DST.** A single offset captured today was applied to every
  ///    historical day, so shifts either side of a clock change bucketed into
  ///    the wrong local day regardless of the sign.
  ///
  /// A real zone name fixes both, because Postgres then applies the offset that
  /// was actually in force on each date.
  static Future<String> _localTimeZoneName() async {
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      final identifier = name.identifier;
      if (identifier.isNotEmpty) return identifier;
    } catch (_) {
      // Fall through.
    }
    // UTC rather than a fixed offset: bucketing a few hours out is a visible,
    // explicable error, whereas a POSIX-parsed offset is silently backwards.
    return 'UTC';
  }
}

/// Stable across syncs so re-importing the same day replaces its shift instead
/// of adding a duplicate. The `manual-` and `tracked-` prefixes used for
/// hand-entered and GPS-tracked shifts cannot collide with this.
///
/// Takes the raw provider id rather than a [WorkPlatform]. Everything the app
/// does not recognise maps to `WorkPlatform.other`, so keying on the enum made
/// every unrecognised platform share one id per day — and a day with two of
/// them lost the earnings of whichever synced first.
String importedShiftId(String providerId, DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final dayOfMonth = day.day.toString().padLeft(2, '0');
  return 'imported:$providerId:${day.year}-$month-$dayOfMonth';
}
