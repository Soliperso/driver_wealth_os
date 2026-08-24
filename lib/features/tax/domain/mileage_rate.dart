/// The IRS standard mileage rate, as published data rather than a constant.
///
/// Deliberately a list of dated bands, not a map keyed by tax year. The IRS
/// changes the rate mid-year when fuel prices move enough — it did so on
/// 1 July 2022 and again on 1 July 2026 — so a year-keyed table would quietly
/// deduct the wrong amount for half of those years. A shift is priced by the
/// day it was worked, not by the year it falls in.
///
/// Figures are transcribed from the IRS "Standard mileage rates" table:
/// https://www.irs.gov/tax-professionals/standard-mileage-rates
library;

/// One published rate and the span it applies to.
class MileageRateBand {
  const MileageRateBand({
    required this.from,
    required this.to,
    required this.centsPerMile,
  });

  /// First day the rate applies, inclusive.
  final DateTime from;

  /// Last day the rate applies, inclusive.
  final DateTime to;

  /// Cents rather than dollars: the IRS publishes cents, and 67 is exact where
  /// 0.67 is not. The division happens once, in [dollarsPerMile].
  final double centsPerMile;

  double get dollarsPerMile => centsPerMile / 100;

  bool covers(DateTime day) => !day.isBefore(from) && !day.isAfter(_endOf(to));

  /// The band's own label, e.g. "Jan 1 – Jun 30, 2026 · 72.5¢/mi".
  String get label {
    final wholeYear = from.month == 1 && from.day == 1 && to.month == 12;
    final rate = centsPerMile == centsPerMile.roundToDouble()
        ? centsPerMile.toStringAsFixed(0)
        : centsPerMile.toStringAsFixed(1);
    if (wholeYear) return '${from.year} · $rate¢/mi';
    return '${_month(from)} ${from.day} – ${_month(to)} ${to.day}, '
        '${to.year} · $rate¢/mi';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _month(DateTime day) => _months[day.month - 1];

  static DateTime _endOf(DateTime day) =>
      DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
}

abstract final class MileageRates {
  /// Newest first, which is the order [bandFor] scans and the order a driver
  /// reads them in.
  ///
  /// `final`, not `const`: `DateTime` has no const constructor.
  ///
  /// Verified against irs.gov on 21 August 2026. When the IRS publishes a new
  /// rate, add a band — do not edit an existing one. A past year's deduction
  /// must not change under a driver who has already filed on it.
  static final bands = <MileageRateBand>[
    MileageRateBand(
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 12, 31),
      centsPerMile: 76,
    ),
    MileageRateBand(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 6, 30),
      centsPerMile: 72.5,
    ),
    MileageRateBand(
      from: DateTime(2025, 1, 1),
      to: DateTime(2025, 12, 31),
      centsPerMile: 70,
    ),
    MileageRateBand(
      from: DateTime(2024, 1, 1),
      to: DateTime(2024, 12, 31),
      centsPerMile: 67,
    ),
    MileageRateBand(
      from: DateTime(2023, 1, 1),
      to: DateTime(2023, 12, 31),
      centsPerMile: 65.5,
    ),
    MileageRateBand(
      from: DateTime(2022, 7, 1),
      to: DateTime(2022, 12, 31),
      centsPerMile: 62.5,
    ),
    MileageRateBand(
      from: DateTime(2022, 1, 1),
      to: DateTime(2022, 6, 30),
      centsPerMile: 58.5,
    ),
  ];

  /// The most recent tax year the table covers. Beyond this the app has no
  /// published rate and says so rather than extrapolating.
  static int get latestPublishedYear => bands.first.to.year;

  /// The rate in force on [day], or null when the day falls outside every
  /// published band.
  ///
  /// Null rather than a fallback, because there is no honest guess: a shift in
  /// a year the IRS has not published yet has no standard rate, and inventing
  /// one would put a made-up number on a tax return.
  static MileageRateBand? bandFor(DateTime day) {
    for (final band in bands) {
      if (band.covers(day)) return band;
    }
    return null;
  }

  /// The deduction for [miles] driven on [day], or null when no rate is
  /// published for it.
  static double? deductionFor(DateTime day, double miles) {
    if (!miles.isFinite || miles <= 0) return 0;
    final band = bandFor(day);
    if (band == null) return null;
    return _currency(miles * band.dollarsPerMile);
  }

  /// The bands touching [year], newest first.
  ///
  /// A year with a mid-year change returns two, which is what the tax screen
  /// has to show — a single blended figure would be a rate the IRS never
  /// published and no driver could reconcile against their own return.
  static List<MileageRateBand> bandsForYear(int year) => [
    for (final band in bands)
      if (band.from.year == year || band.to.year == year) band,
  ];

  static double _currency(num value) => (value * 100).round() / 100;
}
