/// Estimated-tax quarters, and what to put aside for them.
///
/// A gig driver is self-employed: nothing is withheld, and the IRS expects
/// payment four times a year rather than once. The single most common way a
/// driver in this line of work gets hurt is reaching April with the money
/// already spent.
///
/// This is arithmetic on a rate the driver chooses, not a tax computation. The
/// real figure depends on filing status, a spouse's withholding, other income,
/// the QBI deduction and the self-employment adjustment — none of which the
/// app knows or asks for. Everything here is framed as "set aside", never as
/// "you owe".
library;

/// One estimated-tax period and the date its payment is due.
class TaxQuarter {
  const TaxQuarter({
    required this.number,
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
  });

  final int number;

  /// Income earned in this window is what the payment covers.
  final DateTime periodStart;
  final DateTime periodEnd;

  /// When the payment is due — usually the 15th, and note that the IRS
  /// quarters are not three months each: Q2 covers two months and Q4's payment
  /// falls in the following January.
  final DateTime dueDate;

  String get label => 'Q$number';

  bool covers(DateTime day) =>
      !day.isBefore(periodStart) &&
      !day.isAfter(
        DateTime(periodEnd.year, periodEnd.month, periodEnd.day, 23, 59, 59),
      );

  bool isDueAfter(DateTime now) => dueDate.isAfter(now);
}

abstract final class TaxQuarters {
  /// The four estimated-tax periods for [year].
  ///
  /// Dates are the statutory ones. The IRS shifts a due date that lands on a
  /// weekend or holiday to the next business day; that adjustment is not
  /// modelled, so a driver should treat these as "on or just before".
  static List<TaxQuarter> forYear(int year) => [
    TaxQuarter(
      number: 1,
      periodStart: DateTime(year, 1, 1),
      periodEnd: DateTime(year, 3, 31),
      dueDate: DateTime(year, 4, 15),
    ),
    TaxQuarter(
      number: 2,
      periodStart: DateTime(year, 4, 1),
      periodEnd: DateTime(year, 5, 31),
      dueDate: DateTime(year, 6, 15),
    ),
    TaxQuarter(
      number: 3,
      periodStart: DateTime(year, 6, 1),
      periodEnd: DateTime(year, 8, 31),
      dueDate: DateTime(year, 9, 15),
    ),
    TaxQuarter(
      number: 4,
      periodStart: DateTime(year, 9, 1),
      periodEnd: DateTime(year, 12, 31),
      // The one that catches people out: it is due in the new year.
      dueDate: DateTime(year + 1, 1, 15),
    ),
  ];

  /// The next payment due after [now], or null once the year's four have
  /// passed.
  static TaxQuarter? nextDue(DateTime now, {int? year}) {
    for (final quarter in forYear(year ?? now.year)) {
      if (quarter.isDueAfter(now)) return quarter;
    }
    return null;
  }
}

/// What a driver should hold back, at a rate they set.
class SetAside {
  const SetAside({
    required this.rate,
    required this.netProfit,
    required this.amount,
  });

  /// The share of net profit being held back, 0..1.
  final double rate;

  final double netProfit;

  /// [netProfit] × [rate], floored at zero — a losing period has nothing to set
  /// aside, and a negative "set aside" is not a refund.
  final double amount;

  /// A common starting point for self-employment: roughly 15.3% SE tax plus a
  /// low-bracket income tax. Deliberately a default the driver can change, not
  /// a recommendation, because the right number is personal.
  static const defaultRate = .25;

  factory SetAside.of(double netProfit, {double rate = defaultRate}) {
    final safeRate = rate.isFinite ? rate.clamp(0.0, 1.0).toDouble() : 0.0;
    final held = netProfit <= 0 ? 0.0 : netProfit * safeRate;
    return SetAside(
      rate: safeRate,
      netProfit: netProfit,
      amount: (held * 100).round() / 100,
    );
  }
}
