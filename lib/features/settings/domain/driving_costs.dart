/// What a mile actually costs this driver.
///
/// The app tracks miles by GPS but had no way to price the fuel burned over
/// them, so fuel only ever reached the numbers if the driver typed it in by
/// hand. Everything needed to price it — how far the car goes on a unit of
/// energy, and what that unit costs — lives here, along with the derived rates,
/// so no caller re-derives the arithmetic.
library;

enum EnergySource {
  gasoline('Gas', 'MPG', 'Price per gallon', 'gal', 25, 3.50),
  hybrid('Hybrid', 'MPG', 'Price per gallon', 'gal', 45, 3.50),
  electric('Electric', 'Miles per kWh', 'Price per kWh', 'kWh', 3.5, .17);

  const EnergySource(
    this.label,
    this.efficiencyLabel,
    this.priceLabel,
    this.unit,
    this.defaultEfficiency,
    this.defaultPrice,
  );

  /// Shown on the Settings segmented control.
  final String label;

  final String efficiencyLabel;
  final String priceLabel;
  final String unit;
  final double defaultEfficiency;
  final double defaultPrice;

  static EnergySource fromName(Object? value) => EnergySource.values.firstWhere(
    (source) => source.name == value,
    orElse: () => EnergySource.gasoline,
  );
}

class DrivingCosts {
  const DrivingCosts({
    this.energySource = EnergySource.gasoline,
    this.fuelEfficiency = defaultFuelEfficiency,
    this.fuelPrice = defaultFuelPrice,
    this.vehicleCostPerMile = defaultVehicleCostPerMile,
  });

  /// Roughly the US new-car average. Only a starting point — the whole reason
  /// this is a setting is that a Prius and an F-150 are not the same business.
  static const defaultFuelEfficiency = 25.0;
  static const defaultFuelPrice = 3.50;

  /// Rough national average for maintenance, tyres and depreciation. Used until
  /// the driver sets their own rate, and applied to imported shifts, which
  /// arrive with no cost data of any kind.
  static const defaultVehicleCostPerMile = 0.30;

  final EnergySource energySource;

  /// Miles per gallon, or miles per kWh when [energySource] is electric.
  final double fuelEfficiency;

  /// Dollars per gallon, or per kWh.
  final double fuelPrice;

  /// Maintenance, tyres and depreciation — deliberately not fuel, so the two
  /// can be reasoned about (and entered) separately.
  final double vehicleCostPerMile;

  /// Zero rather than infinity when efficiency is missing: a driver who has not
  /// filled this in should see fuel excluded, not see every shift wiped out.
  double get fuelCostPerMile =>
      fuelEfficiency <= 0 ? 0 : _currency4(fuelPrice / fuelEfficiency);

  double get allInCostPerMile =>
      _currency4(vehicleCostPerMile + fuelCostPerMile);

  /// The fuel burned over [miles], rounded to cents for entry into a form.
  double estimatedFuel(double miles) {
    if (!miles.isFinite || miles <= 0) return 0;
    return _currency(miles * fuelCostPerMile);
  }

  /// True cost of [miles] driven — fuel plus wear.
  double estimatedRunningCost(double miles) {
    if (!miles.isFinite || miles <= 0) return 0;
    return _currency(miles * allInCostPerMile);
  }

  String get efficiencyLabel => energySource.efficiencyLabel;
  String get priceLabel => energySource.priceLabel;

  DrivingCosts copyWith({
    EnergySource? energySource,
    double? fuelEfficiency,
    double? fuelPrice,
    double? vehicleCostPerMile,
  }) => DrivingCosts(
    energySource: energySource ?? this.energySource,
    fuelEfficiency: fuelEfficiency ?? this.fuelEfficiency,
    fuelPrice: fuelPrice ?? this.fuelPrice,
    vehicleCostPerMile: vehicleCostPerMile ?? this.vehicleCostPerMile,
  );

  @override
  bool operator ==(Object other) =>
      other is DrivingCosts &&
      other.energySource == energySource &&
      other.fuelEfficiency == fuelEfficiency &&
      other.fuelPrice == fuelPrice &&
      other.vehicleCostPerMile == vehicleCostPerMile;

  @override
  int get hashCode =>
      Object.hash(energySource, fuelEfficiency, fuelPrice, vehicleCostPerMile);

  static double _currency(num value) => (value * 100).round() / 100;

  /// Per-mile rates are cents-per-mile small; rounding them to cents would turn
  /// a 4¢/mile EV into 4¢ or 0¢ depending on the wind.
  static double _currency4(num value) => (value * 10000).round() / 10000;
}
