import 'shift.dart';

class ShiftSummary {
  const ShiftSummary({
    required this.gross,
    required this.netProfit,
    required this.hours,
    required this.miles,
    required this.shiftCount,
    required this.directExpenses,
  });

  factory ShiftSummary.from(Iterable<Shift> shifts) {
    final uniqueShifts = <String, Shift>{};
    for (final shift in shifts) {
      uniqueShifts.putIfAbsent(shift.id, () => shift);
    }

    var gross = 0.0;
    var netProfit = 0.0;
    var hours = 0.0;
    var miles = 0.0;
    var directExpenses = 0.0;
    for (final shift in uniqueShifts.values) {
      gross += shift.gross;
      netProfit += shift.netProfit;
      hours += shift.hours;
      miles += shift.miles;
      directExpenses += shift.directExpenses;
    }

    return ShiftSummary(
      gross: _currency(gross),
      netProfit: _currency(netProfit),
      hours: hours,
      miles: miles,
      shiftCount: uniqueShifts.length,
      directExpenses: _currency(directExpenses),
    );
  }

  final double gross;
  final double netProfit;
  final double hours;
  final double miles;
  final int shiftCount;

  /// Fuel, tolls, parking — what the driver paid out of pocket, as opposed to
  /// the per-mile allowance the vehicle is quietly costing them.
  final double directExpenses;

  double get netPerHour => hours == 0 ? 0 : netProfit / hours;
  double get netPerMile => miles == 0 ? 0 : netProfit / miles;
  double get keepRate => gross == 0 ? 0 : netProfit / gross;

  /// Everything the driving cost: direct expenses plus the per-mile vehicle
  /// allowance. Derived from the totals rather than re-summed, because
  /// [netProfit] is defined as gross minus exactly those two, so this is exact
  /// and cannot drift from the profit figure shown beside it.
  double get totalExpenses => _currency(gross - netProfit);

  /// The per-mile vehicle allowance, derived from [totalExpenses] rather than
  /// re-summed from the shifts. Summing it independently lets rounding drift by
  /// a cent, and a breakdown whose parts do not add up to the headline figure
  /// is worse than no breakdown at all.
  double get vehicleCost => _currency(totalExpenses - directExpenses);

  static double _currency(double value) => (value * 100).round() / 100;
}
