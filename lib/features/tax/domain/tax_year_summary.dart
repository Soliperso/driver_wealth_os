import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_summary.dart';
import 'expense.dart';
import 'mileage_rate.dart';

/// Which of the two vehicle-cost methods the IRS allows produced the larger
/// deduction.
enum DeductionMethod {
  /// Business miles × the published rate. Covers fuel, maintenance, insurance
  /// and depreciation together — nothing vehicle-related may be deducted on
  /// top of it.
  standardMileage,

  /// The driver's real vehicle running costs instead.
  actualExpenses,
}

/// A driver's year, arranged the way a tax return asks for it.
///
/// The one number this exists to produce is the comparison: standard mileage
/// against actual expenses, and which is worth more. A gig driver has both
/// inputs already — the app has been measuring miles by GPS and collecting
/// fuel and vehicle costs all year — and almost none of them know the two are
/// alternatives, let alone which way round it falls for their car.
///
/// Nothing here is tax advice and nothing here is filed. It is arithmetic over
/// the driver's own records, with the method rules stated so they can check it.
class TaxYearSummary {
  const TaxYearSummary({
    required this.year,
    required this.rateBands,
    required this.shiftSummary,
    required this.deductibleMiles,
    required this.standardMileageDeduction,
    required this.unratedMiles,
    required this.vehicleExpenses,
    required this.otherExpenses,
    required this.expensesByCategory,
  });

  final int year;

  /// Every published rate touching this year — two when the IRS changed it
  /// mid-year, which is why the deduction is accumulated per shift rather than
  /// computed from a single annual rate.
  final List<MileageRateBand> rateBands;

  /// Gross, hours and costs across every shift in the year.
  final ShiftSummary shiftSummary;

  /// Business miles with a published rate behind them.
  final double deductibleMiles;

  /// [deductibleMiles] priced at the rate in force on each shift's own day.
  final double standardMileageDeduction;

  /// Miles in a year the IRS has not published a rate for. Surfaced rather
  /// than silently dropped: a driver whose total looks low is entitled to know
  /// that some of their driving could not be priced yet.
  final double unratedMiles;

  /// Vehicle running costs the driver recorded — the per-shift fuel, tolls and
  /// parking, plus their vehicle-wear allowance, plus any standalone expense
  /// filed under a vehicle category.
  ///
  /// This is the figure that competes with [standardMileageDeduction]. The two
  /// are alternatives; claiming both would deduct the same cost twice.
  final double vehicleExpenses;

  /// Everything deductible that is not about running the car — phone, service
  /// fees, supplies. Claimable alongside *either* vehicle method.
  final double otherExpenses;

  final Map<ExpenseCategory, double> expensesByCategory;

  double get gross => shiftSummary.gross;
  int get shiftCount => shiftSummary.shiftCount;
  double get hours => shiftSummary.hours;

  /// The larger of the two vehicle methods.
  DeductionMethod get betterMethod =>
      standardMileageDeduction >= vehicleExpenses
      ? DeductionMethod.standardMileage
      : DeductionMethod.actualExpenses;

  double get betterVehicleDeduction =>
      betterMethod == DeductionMethod.standardMileage
      ? standardMileageDeduction
      : vehicleExpenses;

  /// What choosing the better method is worth over the other one.
  double get methodAdvantage =>
      _currency((standardMileageDeduction - vehicleExpenses).abs());

  /// Total deductions at the better vehicle method.
  double get totalDeductions => _currency(betterVehicleDeduction + otherExpenses);

  /// Gross minus deductions. Not "taxable income" — that depends on filing
  /// status, other income and the QBI deduction, none of which the app knows.
  double get netBeforeTax => _currency(gross - totalDeductions);

  /// True when some of the year's driving has no published rate, so the
  /// standard-mileage figure is understated and the comparison is provisional.
  bool get isProvisional => unratedMiles > 0;

  /// Builds the year from the driver's own records.
  ///
  /// [vehicleCostPerMile] is only used where a shift carries no rate of its
  /// own; each shift's stored rate wins, so a year priced under an older cost
  /// model is not retroactively repriced.
  factory TaxYearSummary.from({
    required int year,
    required Iterable<Shift> shifts,
    Iterable<Expense> expenses = const [],
  }) {
    final unique = <String, Shift>{};
    for (final shift in shifts) {
      if (shift.completedAt.year != year) continue;
      unique.putIfAbsent(shift.id, () => shift);
    }
    final inYear = unique.values.toList();

    var deductible = 0.0;
    var unrated = 0.0;
    var standard = 0.0;
    for (final shift in inYear) {
      if (shift.miles <= 0) continue;
      final band = MileageRates.bandFor(shift.completedAt);
      if (band == null) {
        unrated += shift.miles;
        continue;
      }
      deductible += shift.miles;
      standard += shift.miles * band.dollarsPerMile;
    }

    final shiftSummary = ShiftSummary.from(inYear);

    final byCategory = <ExpenseCategory, double>{};
    for (final expense in _uniqueExpenses(expenses)) {
      if (expense.incurredOn.year != year) continue;
      byCategory[expense.category] =
          (byCategory[expense.category] ?? 0) + expense.amount;
    }

    // Per-shift direct costs are fuel, tolls and parking, and the vehicle-wear
    // allowance is the rest of running the car. Both belong on the actual-
    // expenses side of the comparison, alongside any standalone vehicle entry.
    var vehicle = shiftSummary.directExpenses + shiftSummary.vehicleCost;
    var other = 0.0;
    for (final entry in byCategory.entries) {
      if (entry.key.isVehicleCost) {
        vehicle += entry.value;
      } else {
        other += entry.value;
      }
    }

    return TaxYearSummary(
      year: year,
      rateBands: MileageRates.bandsForYear(year),
      shiftSummary: shiftSummary,
      deductibleMiles: _round(deductible),
      standardMileageDeduction: _currency(standard),
      unratedMiles: _round(unrated),
      vehicleExpenses: _currency(vehicle),
      otherExpenses: _currency(other),
      expensesByCategory: {
        for (final entry in byCategory.entries)
          entry.key: _currency(entry.value),
      },
    );
  }

  /// The tax years the driver has any record in, newest first.
  static List<int> yearsCovered({
    required Iterable<Shift> shifts,
    Iterable<Expense> expenses = const [],
  }) {
    final years = <int>{
      for (final shift in shifts) shift.completedAt.year,
      for (final expense in expenses) expense.incurredOn.year,
    };
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  static Iterable<Expense> _uniqueExpenses(Iterable<Expense> expenses) {
    final unique = <String, Expense>{};
    for (final expense in expenses) {
      unique.putIfAbsent(expense.id, () => expense);
    }
    return unique.values;
  }

  static double _currency(num value) => (value * 100).round() / 100;
  static double _round(num value) => (value * 10).round() / 10;
}
