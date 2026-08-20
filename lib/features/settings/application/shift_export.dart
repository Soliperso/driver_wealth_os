import '../../shifts/domain/shift.dart';

abstract final class ShiftExport {
  static const _headers = [
    'shift_id',
    'completed_at',
    'platforms',
    'gross_earnings',
    'hours',
    'miles',
    'direct_expenses',
    'vehicle_cost_per_mile',
    'vehicle_cost',
    'true_profit',
    'source',
  ];

  static String csv(Iterable<Shift> shifts) {
    final rows = <List<Object?>>[
      _headers,
      for (final shift in shifts)
        [
          shift.id,
          shift.completedAt.toIso8601String(),
          shift.platforms.map((platform) => platform.displayName).join(' + '),
          shift.gross.toStringAsFixed(2),
          shift.hours.toStringAsFixed(4),
          shift.miles.toStringAsFixed(2),
          shift.directExpenses.toStringAsFixed(2),
          shift.vehicleCostPerMile.toStringAsFixed(4),
          shift.vehicleCost.toStringAsFixed(2),
          shift.netProfit.toStringAsFixed(2),
          shift.source.id,
        ],
    ];
    return '${rows.map(_row).join('\r\n')}\r\n';
  }

  static String _row(List<Object?> values) => values.map(_cell).join(',');

  static String _cell(Object? value) {
    final text = value?.toString() ?? '';
    if (!text.contains(',') && !text.contains('"') && !text.contains('\n')) {
      return text;
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
