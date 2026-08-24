import 'driving_costs.dart';
import 'measurement_units.dart';

/// Everything the Settings form owns and saves in one action.
///
/// Bundled rather than carried as a dozen separate callbacks because the form
/// validates and commits as a unit: a driver who fixes their MPG and their
/// hourly floor in one visit expects one save, and a per-field callback made it
/// far too easy to add a field to the model and forget to persist it — which is
/// exactly how the fuel and week-shape settings ended up dead-ended.
class DriverPreferences {
  const DriverPreferences({
    required this.driverName,
    required this.dailyGoal,
    this.drivingCosts = const DrivingCosts(),
    this.hourlyFloor = defaultHourlyFloor,
    this.weekStartsOn = DateTime.monday,
    this.drivingDaysPerWeek = defaultDrivingDaysPerWeek,
    this.units = const MeasurementUnits(),
  });

  /// The pace the app used to call "healthy" for everyone.
  static const defaultHourlyFloor = 25.0;
  static const defaultDrivingDaysPerWeek = 5;

  final String driverName;
  final double dailyGoal;
  final DrivingCosts drivingCosts;

  /// The lowest hourly profit this driver considers worth the trip.
  final double hourlyFloor;

  /// [DateTime.monday] or [DateTime.sunday] — pay weeks differ by platform, and
  /// a chart that splits the driver's week in half is worse than no chart.
  final int weekStartsOn;

  final int drivingDaysPerWeek;
  final MeasurementUnits units;

  /// What a full working week at [dailyGoal] comes to.
  double get weeklyGoal => (dailyGoal * drivingDaysPerWeek * 100).round() / 100;

  DriverPreferences copyWith({
    String? driverName,
    double? dailyGoal,
    DrivingCosts? drivingCosts,
    double? hourlyFloor,
    int? weekStartsOn,
    int? drivingDaysPerWeek,
    MeasurementUnits? units,
  }) => DriverPreferences(
    driverName: driverName ?? this.driverName,
    dailyGoal: dailyGoal ?? this.dailyGoal,
    drivingCosts: drivingCosts ?? this.drivingCosts,
    hourlyFloor: hourlyFloor ?? this.hourlyFloor,
    weekStartsOn: weekStartsOn ?? this.weekStartsOn,
    drivingDaysPerWeek: drivingDaysPerWeek ?? this.drivingDaysPerWeek,
    units: units ?? this.units,
  );

  @override
  bool operator ==(Object other) =>
      other is DriverPreferences &&
      other.driverName == driverName &&
      other.dailyGoal == dailyGoal &&
      other.drivingCosts == drivingCosts &&
      other.hourlyFloor == hourlyFloor &&
      other.weekStartsOn == weekStartsOn &&
      other.drivingDaysPerWeek == drivingDaysPerWeek &&
      other.units == units;

  @override
  int get hashCode => Object.hash(
    driverName,
    dailyGoal,
    drivingCosts,
    hourlyFloor,
    weekStartsOn,
    drivingDaysPerWeek,
    units,
  );
}
