import 'shift.dart';

class ShiftSummary {
  const ShiftSummary({
    required this.gross,
    required this.netProfit,
    required this.hours,
    required this.miles,
    required this.shiftCount,
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
    for (final shift in uniqueShifts.values) {
      gross += shift.gross;
      netProfit += shift.netProfit;
      hours += shift.hours;
      miles += shift.miles;
    }

    return ShiftSummary(
      gross: _currency(gross),
      netProfit: _currency(netProfit),
      hours: hours,
      miles: miles,
      shiftCount: uniqueShifts.length,
    );
  }

  final double gross;
  final double netProfit;
  final double hours;
  final double miles;
  final int shiftCount;

  double get netPerHour => hours == 0 ? 0 : netProfit / hours;
  double get netPerMile => miles == 0 ? 0 : netProfit / miles;
  double get keepRate => gross == 0 ? 0 : netProfit / gross;

  static double _currency(double value) => (value * 100).round() / 100;
}
