import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../shifts/domain/shift.dart';
import '../../tax/domain/expense.dart';
import '../domain/measurement_units.dart';

/// Writes a driver's records out as a spreadsheet they can keep.
///
/// The history is the driver's own record of their year, and at tax time it has
/// to be able to leave the app as a file — not as a screenshot of a chart. CSV
/// rather than a bespoke format because the destination is always someone
/// else's spreadsheet or accountant.
///
/// Sessions and standalone expenses go in **one** file, distinguished by a
/// leading `Record` column. A driver's costs are not a separate story from their
/// earnings — the year only balances when both are in front of you — and one
/// attachment is one thing to forward to an accountant. The two record types
/// fill disjoint blocks of columns and leave the other side empty, so no column
/// ever holds two different kinds of number and every one of them stays
/// summable on its own.
///
/// Distances are written in the driver's chosen unit and the column is named
/// accordingly, so a kilometre-based driver never has to remember that the
/// number is secretly miles. Money is written unformatted — no symbol, no
/// thousands separator — because a spreadsheet needs a number it can add up,
/// not a label. The currency is named in the column header instead.
final class HistoryExport {
  const HistoryExport({this.units = const MeasurementUnits()});

  final MeasurementUnits units;

  /// One ledger, newest first, matching the order the driver sees in History.
  ///
  /// [year] restricts both record types to a single tax year — what the Taxes
  /// tab exports, since a filing covers one year and nothing else. Omitted, the
  /// whole history comes out, which is what a personal backup wants.
  String toCsv(
    List<Shift> shifts, {
    List<Expense> expenses = const [],
    int? year,
  }) {
    final date = DateFormat('yyyy-MM-dd');
    final time = DateFormat('HH:mm');
    final code = units.currency.code;
    final unit = units.distance.symbol;

    final rows = <List<String>>[
      [
        // First column so a spreadsheet can filter on it before anything else.
        'Record',
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
        // The expense block. Empty on a session row.
        'Category',
        'Schedule C line',
        'Vehicle cost?',
        'Amount ($code)',
        'Note',
        'Source',
      ],
    ];

    // Interleaved on one date axis rather than stacked in two blocks: the file
    // is a ledger, and a cost belongs beside the week it was incurred in.
    final entries = <(DateTime, List<String>)>[
      for (final shift in shifts)
        if (year == null || shift.completedAt.year == year)
          (shift.completedAt, _sessionRow(shift, date, time)),
      for (final expense in expenses)
        if (year == null || expense.occurredIn(year))
          (expense.incurredOn, _expenseRow(expense, date)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    rows.addAll(entries.map((entry) => entry.$2));

    return rows.map((row) => row.map(escapeField).join(',')).join('\r\n');
  }

  List<String> _sessionRow(Shift shift, DateFormat date, DateFormat time) => [
    'Session',
    date.format(shift.completedAt),
    time.format(shift.completedAt),
    // The full list, not the "+ 2 more" label: a spreadsheet has room and
    // the driver may want to filter on it.
    shift.platformsByEarnings.map((p) => p.displayName).join(' + '),
    _amount(shift.gross),
    shift.hours.toStringAsFixed(2),
    shift.miles.toStringAsFixed(1),
    _amount(shift.directExpenses),
    _amount(shift.vehicleCost),
    _amount(shift.totalExpenses),
    _amount(shift.netProfit),
    _amount(shift.netPerHour),
    // Derived from the two columns beside it rather than from the stored
    // rate, so the spreadsheet reconciles exactly.
    _amount(shift.miles == 0 ? 0 : shift.netProfit / shift.miles),
    (shift.keepRate * 100).toStringAsFixed(1),
    // The expense block, empty for a session.
    '', '', '', '', '',
    shift.source.id,
  ];

  List<String> _expenseRow(Expense expense, DateFormat date) => [
    'Expense',
    date.format(expense.incurredOn),
    // No time: an expense is dated, not clocked. Every session-only column
    // stays empty rather than carrying a zero, because a zero would be added
    // up as though the driver had earned nothing that day.
    '', '', '', '', '', '', '', '', '', '', '', '',
    expense.category.label,
    expense.category.scheduleCLine,
    // Spelled out rather than left as a bare flag: this is the column that
    // decides whether the cost can be claimed alongside the standard mileage
    // rate, and an accountant reading the file has no other way to tell.
    expense.category.isVehicleCost ? 'Yes' : 'No',
    _amount(expense.amount),
    expense.note,
    // Expenses are only ever hand-entered; there is no import for them.
    'manual',
  ];

  /// Writes the CSV to a temporary file and hands it to the system share sheet.
  ///
  /// Returns false when there is nothing to export, so the caller can say so
  /// rather than opening a share sheet on an empty file.
  Future<bool> share(
    List<Shift> shifts, {
    List<Expense> expenses = const [],
    int? year,
    DateTime? now,
  }) async {
    final csv = toCsv(shifts, expenses: expenses, year: year);
    // Checked on the rendered file rather than on the inputs, so a year with
    // records in neither list is refused the same way an empty app is — and a
    // driver who has only logged expenses can still export.
    if (csv.split('\r\n').length < 2) return false;

    final stamp =
        year?.toString() ??
        DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
    // The filename is what an accountant sees in their inbox, so it carries the
    // product name rather than the package's.
    final name = 'keeprate-$stamp.csv';
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$name');
    await file.writeAsString(csv, flush: true);

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          fileNameOverrides: [name],
          subject: year == null
              ? 'Keeprate records'
              : 'Keeprate records — $year',
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
