enum DistanceUnit {
  miles('Miles', 'mi', 1),
  kilometers('Kilometers', 'km', 1.609344);

  const DistanceUnit(this.label, this.symbol, this.unitsPerMile);

  final String label;
  final String symbol;
  final double unitsPerMile;

  double fromMiles(double miles) => miles * unitsPerMile;

  double toMiles(double distance) => distance / unitsPerMile;

  double rateFromPerMile(double rate) => rate / unitsPerMile;

  double rateToPerMile(double rate) => rate * unitsPerMile;

  static DistanceUnit fromName(Object? value) => DistanceUnit.values.firstWhere(
    (unit) => unit.name == value,
    orElse: () => DistanceUnit.miles,
  );
}
