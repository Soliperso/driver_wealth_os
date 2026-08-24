import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../shifts/domain/shift.dart';
import '../domain/measurement_units.dart';

/// Writes a driver's history out as a spreadsheet they can keep.
///
/// The history is the driver's own record of their year, and at tax time it has
/// to be able to leave the app as a file — not as a screenshot of a chart. CSV
/// rather than a bespoke format because the destination is always someone
/// else's spreadsheet or accountant.
///
/// Distances are written in the driver's chosen unit and the column is named
/// accordingly, so a kilometre-based driver never has to remember that the
/// number is secretly miles. Money is written unformatted — no symbol, no
/// thousands separator — because a spreadsheet needs a number it can add up,
/// not a label. The currency is named in the column header instead.
final class HistoryExport {
  const HistoryExport({this.units = const MeasurementUnits()});

  final MeasurementUnits units;

  /// Newest first, matching the order the driver sees in History.
  String toCsv(List<Shift> shifts) {
    final date = DateFormat('yyyy-MM-dd');
    final time = DateFormat('HH:mm');
    final code = units.currency.code;
    final unit = units.distance.symbol;

    final rows = <List<String>>[
      [
        'Date',
        'Time',
        'Apps',
        'Gross ($code)',
        'Hours',
        'Distance ($unit)',
        'Direct expenses ($code)',
        'Vehicle cost ($code)',
        'Total expenses ($code)',
        'Net profit ($code)',
        'Net per hour ($code)',
        'Net per $unit ($code)',
        'Keep rate (%)',
        'Source',
      ],
    ];

    final ordered = [...shifts]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    for (final shift in ordered) {
      final distance = units.distance.fromMiles(shift.miles);
      rows.add([
        date.format(shift.completedAt),
        time.format(shift.completedAt),
        // The full list, not the "+ 2 more" label: a spreadsheet has room and
        // the driver may want to filter on it.
        shift.platformsByEarnings.map((p) => p.displayName).join(' + '),
        _amount(shift.gross),
        shift.hours.toStringAsFixed(2),
        distance.toStringAsFixed(1),
        _amount(shift.directExpenses),
        _amount(shift.vehicleCost),
        _amount(shift.totalExpenses),
        _amount(shift.netProfit),
        _amount(shift.netPerHour),
        // Per-distance rates are computed from the converted distance, not by
        // converting the per-mile rate, so the column reconciles exactly with
        // the net profit and distance columns beside it.
        _amount(distance == 0 ? 0 : shift.netProfit / distance),
        (shift.keepRate * 100).toStringAsFixed(1),
        shift.source.id,
      ]);
    }

    return rows.map((row) => row.map(escapeField).join(',')).join('\r\n');
  }

  /// Writes the CSV to a temporary file and hands it to the system share sheet.
  ///
  /// Returns false when there is nothing to export, so the caller can say so
  /// rather than opening a share sheet on an empty file.
  Future<bool> share(List<Shift> shifts, {DateTime? now}) async {
    if (shifts.isEmpty) return false;

    final stamp = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/driver-wealth-$stamp.csv');
    await file.writeAsString(toCsv(shifts), flush: true);

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          fileNameOverrides: ['driver-wealth-$stamp.csv'],
          subject: 'Driver Wealth session history',
        ),
      );
    } finally {
      // The driver's entire financial history, under a predictable name, in a
      // directory the OS is free to leave in place indefinitely. The share
      // sheet has already taken its own copy by the time this returns, so
      // nothing is lost by removing ours.
      //
      // Swallowed rather than surfaced: the export succeeded, and a failure to
      // tidy up is not something the driver can act on.
      try {
        if (file.existsSync()) await file.delete();
      } catch (_) {}
    }
    return true;
  }

  /// Two decimals, no symbol and no grouping — a spreadsheet has to be able to
  /// parse this as a number.
  static String _amount(double value) => value.toStringAsFixed(2);

  /// RFC 4180: quote whenever the value contains a delimiter, a quote or a
  /// newline, and double any embedded quote. Platform display names are the
  /// realistic source of a comma here.
  ///
  /// Exposed for testing because it is the rule that decides whether one comma
  /// in a name silently shifts every column after it, and no fixture built from
  /// the real [WorkPlatform] list can produce that case.
  @visibleForTesting
  static String escapeField(String value) {
    if (!value.contains(RegExp('[",\r\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
