/// How distances and money are shown — never how they are stored.
///
/// Shifts hold miles and a plain double for money, because a stored figure that
/// changes meaning when a preference changes is a corruption waiting to happen.
/// Everything here is applied at the edges: on the way to a label, and on the
/// way back from a text field.
library;

import 'package:intl/intl.dart';

enum DistanceUnit {
  miles('mi', 'Miles', 'mile', 1),

  /// One statute mile. Exact by definition, so a round trip through the setting
  /// cannot drift a driver's mileage.
  kilometres('km', 'Kilometres', 'kilometre', 1.609344);

  const DistanceUnit(this.symbol, this.label, this.singular, this.perMile);

  final String symbol;

  /// Shown on the Settings segmented control.
  final String label;

  final String singular;

  /// How many of this unit make one mile.
  final double perMile;

  /// Miles as stored → the number to put in front of the driver.
  double fromMiles(double miles) => miles * perMile;

  /// What the driver typed → miles to store.
  double toMiles(double value) => perMile == 1 ? value : value / perMile;

  /// The fuel volume that goes with this distance. Not a separate preference:
  /// nobody measures their car in kilometres per gallon, so the two travel
  /// together and offering them independently would only invite an incoherent
  /// pair.
  VolumeUnit get volume =>
      this == DistanceUnit.miles ? VolumeUnit.gallons : VolumeUnit.litres;

  static DistanceUnit fromName(Object? value) => DistanceUnit.values.firstWhere(
    (unit) => unit.name == value,
    orElse: () => DistanceUnit.miles,
  );
}

enum VolumeUnit {
  gallons('gal', 'gallon', 1),

  /// US liquid gallons, matching the `gal` the app has always meant.
  litres('L', 'litre', 3.785411784);

  const VolumeUnit(this.symbol, this.singular, this.perGallon);

  final String symbol;
  final String singular;

  /// How many of this unit make one US gallon.
  final double perGallon;

  double fromGallons(double gallons) => gallons * perGallon;

  double toGallons(double value) => perGallon == 1 ? value : value / perGallon;
}

/// The currencies the app offers explicitly.
///
/// A closed list rather than every ISO code: each entry has to have a symbol
/// that renders in the app's font and a locale whose grouping and decimal marks
/// are right, and neither can be derived from a code alone.
enum SupportedCurrency {
  usd('USD', r'$', 'en_US', 'US dollar'),
  cad('CAD', r'CA$', 'en_CA', 'Canadian dollar'),
  aud('AUD', r'A$', 'en_AU', 'Australian dollar'),
  gbp('GBP', '£', 'en_GB', 'British pound'),
  eur('EUR', '€', 'en_IE', 'Euro'),
  nzd('NZD', r'NZ$', 'en_NZ', 'New Zealand dollar');

  const SupportedCurrency(this.code, this.symbol, this.locale, this.label);

  final String code;
  final String symbol;

  /// Drives grouping and decimal separators, not the symbol — the symbol is
  /// pinned above so a euro never renders as `US$`.
  final String locale;

  final String label;

  static SupportedCurrency fromCode(Object? value) =>
      SupportedCurrency.values.firstWhere(
        (currency) => currency.code == value,
        orElse: () => SupportedCurrency.usd,
      );
}

/// The display pair, carried together because nothing ever needs one without
/// the other.
class MeasurementUnits {
  const MeasurementUnits({
    this.distance = DistanceUnit.miles,
    this.currency = SupportedCurrency.usd,
  });

  final DistanceUnit distance;
  final SupportedCurrency currency;

  MeasurementUnits copyWith({
    DistanceUnit? distance,
    SupportedCurrency? currency,
  }) => MeasurementUnits(
    distance: distance ?? this.distance,
    currency: currency ?? this.currency,
  );

  VolumeUnit get volume => distance.volume;

  /// A cost stored per mile → the same cost per the driver's unit.
  ///
  /// Divided, not multiplied: the same money spread over more units is less per
  /// unit, so $0.30/mi is $0.19/km.
  double rateFromPerMile(double perMile) =>
      distance.perMile == 1 ? perMile : perMile / distance.perMile;

  double rateToPerMile(double perUnit) =>
      distance.perMile == 1 ? perUnit : perUnit * distance.perMile;

  /// Efficiency is stored as miles per US gallon, or miles per kWh when the car
  /// is electric.
  ///
  /// Electricity is sold in kWh everywhere, so only the distance half converts
  /// for an EV. A gas car converts both: miles-per-gallon becomes
  /// kilometres-per-litre.
  double efficiencyFromStored(double stored, {required bool electric}) {
    final converted = distance.fromMiles(stored);
    return electric ? converted : converted / volume.perGallon;
  }

  double efficiencyToStored(double shown, {required bool electric}) {
    final inMiles = distance.toMiles(shown);
    return electric ? inMiles : inMiles * volume.perGallon;
  }

  /// Fuel price is stored per US gallon, or per kWh when electric.
  ///
  /// A price per unit scales inversely with the size of the unit: the same
  /// $3.50 that buys a gallon buys 3.785 litres, so a litre costs $0.92.
  double fuelPriceFromStored(double stored, {required bool electric}) =>
      electric ? stored : stored / volume.perGallon;

  double fuelPriceToStored(double shown, {required bool electric}) =>
      electric ? shown : shown * volume.perGallon;

  NumberFormat currencyFormat({int decimals = 2}) => NumberFormat.currency(
    locale: currency.locale,
    symbol: currency.symbol,
    decimalDigits: decimals,
  );

  /// `$1,234.56`, and `-$40.00` for a loss.
  ///
  /// This and the four below are the same surface `Money` offers, but honouring
  /// the driver's chosen currency. `Money` was pinned to `en_US` and a literal
  /// `$`, and it was what Today, History, shift detail and the driving hero all
  /// called — so a driver who picked GBP saw pounds in Settings and dollars
  /// everywhere they actually looked.
  String cents(double value) => currencyFormat().format(value);

  /// `$1,235` — for goals and targets, where cents are noise.
  String whole(double value) => currencyFormat(decimals: 0).format(value);

  /// `$1.2K` — for a chart's value axis, where a full figure would eat the
  /// plot. Falls back to whole units below a thousand, so `$250` stays `$250`
  /// rather than becoming `$0.3K`.
  String compact(double value) => value.abs() < 1000
      ? whole(value)
      : NumberFormat.compactCurrency(
          locale: currency.locale,
          symbol: currency.symbol,
        ).format(value);

  /// Always carries a sign, so a gain reads unambiguously as a gain.
  String signed(double value) => value > 0 ? '+${cents(value)}' : cents(value);

  /// A cost shown inside a breakdown, e.g. `−$60.00`. Uses a true minus sign
  /// (U+2212) rather than a hyphen, which is what the calculation rows want.
  String negated(double value) =>
      value == 0 ? cents(0) : '−${cents(value.abs())}';

  /// `$0.42/mi`, `£0.26/km` — a money-per-distance rate, converted from the
  /// per-mile figure the app stores.
  String perDistance(double perMile) => rateLabel(perMile);

  /// The distance figure alone, in the driver's unit, without the symbol.
  double distanceValue(double miles) => distance.fromMiles(miles);

  /// `$0.30/mi`, `£0.19/km` — the per-distance rate label, which is the one
  /// place both halves of this class meet.
  String rateLabel(double perMile, {int decimals = 2}) =>
      '${currencyFormat(decimals: decimals).format(rateFromPerMile(perMile))}/${distance.symbol}';

  /// `120.5 mi`, `194.0 km`.
  String distanceLabel(double miles, {int decimals = 1}) =>
      '${distance.fromMiles(miles).toStringAsFixed(decimals)} ${distance.symbol}';

  /// What the efficiency field is called, given the energy source's own wording
  /// for the numerator.
  String efficiencyLabel({required bool electric}) => electric
      ? '${distance.label} per kWh'
      : '${distance.label} per ${volume.singular}';

  String fuelPriceLabel({required bool electric}) =>
      electric ? 'Price per kWh' : 'Price per ${volume.singular}';

  @override
  bool operator ==(Object other) =>
      other is MeasurementUnits &&
      other.distance == distance &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(distance, currency);
}
