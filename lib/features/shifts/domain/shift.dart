import '../../accounts/domain/work_platform.dart';

/// Where a shift's figures came from.
///
/// Imported shifts are aggregated from a connected platform's gig feed, which
/// reports earnings, duration and distance but never fuel, tolls or parking.
/// They therefore start with no direct expenses and the driver is expected to
/// add them, so the two sources must stay distinguishable in the UI.
enum ShiftSource {
  manual('manual'),
  imported('imported'),

  /// Hours and miles came from a live driving session; the money was still
  /// supplied by the driver or an earnings source afterwards.
  tracked('tracked');

  const ShiftSource(this.id);

  final String id;

  static ShiftSource fromId(Object? value) => values.firstWhere(
    (source) => source.id == value,
    orElse: () => ShiftSource.manual,
  );
}

class Shift {
  const Shift({
    required this.id,
    required this.platform,
    required this.gross,
    required this.hours,
    required this.miles,
    required this.directExpenses,
    required this.vehicleCostPerMile,
    required this.completedAt,
    this.source = ShiftSource.manual,
  });

  final String id;
  final WorkPlatform platform;
  final double gross;
  final double hours;
  final double miles;
  final double directExpenses;
  final double vehicleCostPerMile;
  final DateTime completedAt;
  final ShiftSource source;

  double get vehicleCost => _currency(miles * vehicleCostPerMile);
  double get totalExpenses => _currency(directExpenses + vehicleCost);
  double get netProfit => _currency(gross - totalExpenses);
  double get netPerHour => hours == 0 ? 0 : netProfit / hours;
  double get netPerMile => miles == 0 ? 0 : netProfit / miles;
  double get keepRate => gross == 0 ? 0 : netProfit / gross;

  bool occurredOn(DateTime date) =>
      completedAt.year == date.year &&
      completedAt.month == date.month &&
      completedAt.day == date.day;

  Shift copyWith({
    double? gross,
    double? hours,
    double? miles,
    double? directExpenses,
    double? vehicleCostPerMile,
    DateTime? completedAt,
  }) => Shift(
    id: id,
    platform: platform,
    gross: gross ?? this.gross,
    hours: hours ?? this.hours,
    miles: miles ?? this.miles,
    directExpenses: directExpenses ?? this.directExpenses,
    vehicleCostPerMile: vehicleCostPerMile ?? this.vehicleCostPerMile,
    completedAt: completedAt ?? this.completedAt,
    source: source,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'platform': platform.id,
    'gross': gross,
    'hours': hours,
    'miles': miles,
    'directExpenses': directExpenses,
    'vehicleCostPerMile': vehicleCostPerMile,
    'completedAt': completedAt.toIso8601String(),
    'source': source.id,
  };

  factory Shift.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final platformId = json['platform'];
    final completedAt = DateTime.tryParse(json['completedAt'] as String? ?? '');
    if (id is! String || id.isEmpty || completedAt == null) {
      throw const FormatException('Invalid shift identity');
    }
    return Shift(
      id: id,
      platform: WorkPlatform.values.firstWhere(
        (platform) => platform.id == platformId,
        orElse: () => WorkPlatform.other,
      ),
      gross: _number(json['gross']),
      hours: _number(json['hours']),
      miles: _number(json['miles']),
      directExpenses: _number(json['directExpenses']),
      vehicleCostPerMile: _number(json['vehicleCostPerMile']),
      completedAt: completedAt,
      // Absent on records written before imports existed: they are all manual.
      source: ShiftSource.fromId(json['source']),
    );
  }

  static double _currency(double value) => (value * 100).round() / 100;

  static double _number(Object? value) {
    if (value is num && value.isFinite && value >= 0) {
      return value.toDouble();
    }
    throw const FormatException('Invalid shift amount');
  }
}
