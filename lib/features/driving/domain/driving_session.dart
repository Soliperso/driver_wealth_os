import '../../accounts/domain/work_platform.dart';
import '../../shifts/domain/shift.dart';

/// A live or just-finished driving session.
///
/// Duration is never stored as a running count. Only [startedAt] and
/// [endedAt] are persisted, and elapsed time is derived from them. The OS is
/// free to suspend or kill the app mid-shift; the arithmetic still comes out
/// right afterwards, which an in-memory ticking counter could not guarantee.
class DrivingSession {
  const DrivingSession({
    required this.id,
    required this.startedAt,
    required this.platform,
    this.endedAt,
    this.distanceMeters = 0,
    this.vehicleCostPerMile = 0.30,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final WorkPlatform platform;
  final double distanceMeters;
  final double vehicleCostPerMile;

  bool get isActive => endedAt == null;

  /// Elapsed time, derived rather than counted.
  Duration elapsed({DateTime? now}) =>
      (endedAt ?? now ?? DateTime.now()).difference(startedAt);

  double get miles => distanceMeters / 1609.344;

  double get hours => elapsed().inMilliseconds / Duration.millisecondsPerHour;

  /// What the mileage has already cost in wear, shown live so the driver can
  /// see the meter running against them, not just the hours accruing.
  double get estimatedVehicleCost =>
      ((miles * vehicleCostPerMile) * 100).round() / 100;

  DrivingSession copyWith({
    DateTime? endedAt,
    double? distanceMeters,
    WorkPlatform? platform,
    double? vehicleCostPerMile,
  }) => DrivingSession(
    id: id,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    platform: platform ?? this.platform,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    vehicleCostPerMile: vehicleCostPerMile ?? this.vehicleCostPerMile,
  );

  /// Converts a finished session into the shift the earnings then attach to.
  ///
  /// Hours and miles are the tracked figures; everything monetary is left at
  /// zero because a session knows what was driven, never what was paid.
  Shift toDraftShift({required DateTime endedAt}) {
    final duration = endedAt.difference(startedAt);
    return Shift(
      id: 'tracked-${startedAt.microsecondsSinceEpoch}',
      platform: platform,
      gross: 0,
      hours: _round(duration.inMilliseconds / Duration.millisecondsPerHour, 4),
      miles: _round(distanceMeters / 1609.344, 2),
      directExpenses: 0,
      vehicleCostPerMile: vehicleCostPerMile,
      completedAt: endedAt,
      source: ShiftSource.tracked,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'platform': platform.id,
    'distanceMeters': distanceMeters,
    'vehicleCostPerMile': vehicleCostPerMile,
  };

  static DrivingSession? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (id is! String || id.isEmpty || startedAt == null) return null;
    final distance = json['distanceMeters'];
    final rate = json['vehicleCostPerMile'];
    return DrivingSession(
      id: id,
      startedAt: startedAt,
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
      platform: WorkPlatform.values.firstWhere(
        (platform) => platform.id == json['platform'],
        orElse: () => WorkPlatform.uber,
      ),
      distanceMeters: distance is num && distance.isFinite && distance >= 0
          ? distance.toDouble()
          : 0,
      vehicleCostPerMile: rate is num && rate.isFinite && rate >= 0
          ? rate.toDouble()
          : 0.30,
    );
  }

  static double _round(double value, int places) =>
      double.parse(value.toStringAsFixed(places));
}

/// Formats elapsed time as HH:MM:SS for the live display.
String formatElapsed(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
}
