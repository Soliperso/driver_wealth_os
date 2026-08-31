/// How money and distance are written — never how they are stored.
///
/// The app measures distance in miles and prices everything in US dollars, and
/// stores exactly that. There is deliberately **no conversion anywhere**: a
/// stored number means one thing for the life of the record, and everything
/// here only decides how to spell it.
///
/// That is the whole reason this type still exists rather than each screen
/// reaching for a hardcoded `$` and a literal `mi`. When Today, History, the
/// shift detail and the driving hero each formatted money themselves, they
/// drifted — a figure showed `$1234.56` with no separator on one screen and
/// `$-40.00` on another. One seam keeps them honest.
library;

import 'package:intl/intl.dart';

/// The unit the app measures in. A named value rather than bare strings so
/// `mi`, `Miles` and `mile` are each spelled in exactly one place.
enum DistanceUnit {
  miles('mi', 'Miles', 'mile');

  const DistanceUnit(this.symbol, this.label, this.singular);

  final String symbol;

  /// Title case, for a field label: "Miles driven".
  final String label;

  /// Lower case and singular, for a rate: "Vehicle wear per mile".
  final String singular;
}

/// The volume fuel is sold in. Travels with [DistanceUnit] rather than being a
/// setting of its own: nobody measures a car in kilometres per gallon, so the
/// pair can never be chosen independently.
enum VolumeUnit {
  gallons('gal', 'gallon');

  const VolumeUnit(this.symbol, this.singular);

  final String symbol;
  final String singular;
}

/// The currency the app prices in.
enum SupportedCurrency {
  usd('USD', r'$', 'en_US', 'US dollar');

  const SupportedCurrency(this.code, this.symbol, this.locale, this.label);

  final String code;
  final String symbol;

  /// Drives grouping and decimal marks, not the symbol itself.
  final String locale;

  final String label;
}

/// The formatting seam every screen goes through.
///
/// Carries no choice: there is one unit and one currency. It exists so that a
/// figure is rendered the same way everywhere, and so a future decision to
/// offer another currency has one place to change rather than thirty.
class MeasurementUnits {
  const MeasurementUnits();

  DistanceUnit get distance => DistanceUnit.miles;
  SupportedCurrency get currency => SupportedCurrency.usd;
  VolumeUnit get volume => VolumeUnit.gallons;

  NumberFormat currencyFormat({int decimals = 2}) => NumberFormat.currency(
    locale: currency.locale,
    symbol: currency.symbol,
    decimalDigits: decimals,
  );

  /// `$1,234.56`, and `-$40.00` for a loss.
  String cents(double value) => currencyFormat().format(value);

  /// `$1,235` — for goals and targets, where cents are noise.
  String whole(double value) => currencyFormat(decimals: 0).format(value);

  /// `$1.2K` — for a chart's value axis, where a full figure would eat the
  /// plot. Falls back to whole dollars below a thousand, so `$250` stays `$250`
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

  /// `$0.30/mi` — a money-per-distance rate. The figure is printed as given;
  /// the app stores per-mile rates and shows per-mile rates.
  String rateLabel(double perMile, {int decimals = 2}) =>
      '${currencyFormat(decimals: decimals).format(perMile)}/${distance.symbol}';

  /// `120.5 mi`.
  String distanceLabel(double miles, {int decimals = 1}) =>
      '${miles.toStringAsFixed(decimals)} ${distance.symbol}';

  @override
  bool operator ==(Object other) => other is MeasurementUnits;

  @override
  int get hashCode => (MeasurementUnits).hashCode;
}
