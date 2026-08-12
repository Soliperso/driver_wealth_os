import 'dart:ui';

import 'package:intl/intl.dart';

/// One place that decides how money and metrics are rendered.
///
/// Previously every screen called `toStringAsFixed(2)` behind a hard-coded `$`,
/// which produced `$1234.56` with no thousands separator and put the minus sign
/// in the wrong place on a loss (`$-40.00` rather than `-$40.00`).
///
/// The locale is pinned so figures are stable and testable. Honouring the
/// device locale — and the per-entry `currency` column the backend already
/// stores — is a follow-up, but it now only has to change here.
abstract final class Money {
  static const _locale = 'en_US';

  static final _cents = NumberFormat.simpleCurrency(
    locale: _locale,
    decimalDigits: 2,
  );
  static final _whole = NumberFormat.simpleCurrency(
    locale: _locale,
    decimalDigits: 0,
  );
  static final _plain = NumberFormat.decimalPattern(_locale);

  /// `$1,234.56`, and `-$40.00` for a loss.
  static String cents(double value) => _cents.format(value);

  /// `$1,235` — for goals and targets, where cents are noise.
  static String whole(double value) => _whole.format(value);

  /// Always carries a sign, so a gain reads unambiguously as a gain.
  static String signed(double value) =>
      value > 0 ? '+${cents(value)}' : cents(value);

  /// A cost shown inside a breakdown, e.g. `−$60.00`. Uses a true minus sign
  /// (U+2212) rather than a hyphen, which is what the calculation rows want.
  static String negated(double value) =>
      value == 0 ? cents(0) : '−${cents(value.abs())}';

  static String percent(double value) => '${(value * 100).toStringAsFixed(0)}%';

  static String number(double value, {int decimals = 1}) =>
      value.toStringAsFixed(decimals);

  static String compactNumber(double value) => _plain.format(value);
}

/// Lining, fixed-width digits.
///
/// Without this, proportional digits make stacked figures fail to align — the
/// single clearest tell that a numbers-heavy interface was not designed for
/// numbers.
const tabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
  FontFeature.liningFigures(),
];
