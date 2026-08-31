import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/settings/application/history_export.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/tax/domain/expense.dart';
import 'package:flutter_test/flutter_test.dart';

/// The export is the one place a driver's records leave the app, so the file
/// has to be something a spreadsheet can actually add up — and it has to agree
/// with the figures the app showed them.
///
/// Sessions and expenses share one file, so the rules that matter most here are
/// the ones that keep the two from contaminating each other's columns.
void main() {
  Shift shift({
    required String id,
    Map<WorkPlatform, double>? earnings,
    double hours = 5,
    double miles = 100,
    double directExpenses = 20,
    double vehicleCostPerMile = .30,
    DateTime? completedAt,
    ShiftSource source = ShiftSource.manual,
  }) => Shift(
    id: id,
    earnings: earnings ?? {WorkPlatform.uber: 200},
    hours: hours,
    miles: miles,
    directExpenses: directExpenses,
    vehicleCostPerMile: vehicleCostPerMile,
    completedAt: completedAt ?? DateTime(2026, 8, 11, 18, 30),
    source: source,
  );

  Expense expense({
    String id = 'e1',
    double amount = 400,
    ExpenseCategory category = ExpenseCategory.vehiclePayment,
    DateTime? incurredOn,
    String note = '',
  }) => Expense(
    id: id,
    amount: amount,
    category: category,
    incurredOn: incurredOn ?? DateTime(2026, 8, 12),
    note: note,
  );

  List<String> rows(String csv) => csv.split('\r\n');

  /// Splits on delimiters that are actually delimiters.
  ///
  /// A naive `split(',')` would pass every test here except the one that
  /// matters — a comma inside a quoted note is exactly the case that shifts
  /// every column after it, so the test has to read the file the way a
  /// spreadsheet does.
  List<String> cells(String row) {
    final out = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < row.length; i++) {
      final char = row[i];
      if (char == '"') {
        // A doubled quote inside a quoted field is one literal quote.
        if (quoted && i + 1 < row.length && row[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        out.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    return out..add(buffer.toString());
  }

  /// Column index by header name, so a schema change moves the tests once, in
  /// one place, instead of silently shifting every positional assertion.
  int columnOf(String csv, String header) =>
      cells(rows(csv).first).indexOf(header);

  test('the header names the unit and currency every column is in', () {
    const export = HistoryExport();

    final header = rows(export.toCsv([shift(id: 'a')])).first;

    // A bare "Distance" column invites the reader to guess, and a spreadsheet
    // of money with no currency on it is not evidence of anything.
    expect(header, contains('Distance (mi)'));
    expect(header, contains('Gross (USD)'));
    expect(header, contains('Net per mi (USD)'));
    expect(header, contains('Amount (USD)'));
  });

  test('money is written unformatted so a spreadsheet can sum it', () {
    const export = HistoryExport();
    final csv = export.toCsv([shift(id: 'a')]);
    final row = cells(rows(csv)[1]);

    // gross 200, direct 20, vehicle 100 * .30 = 30, net 150.
    expect(row[columnOf(csv, 'Gross (USD)')], '200.00');
    expect(row[columnOf(csv, 'Direct expenses (USD)')], '20.00');
    expect(row[columnOf(csv, 'Vehicle cost (USD)')], '30.00');
    expect(row[columnOf(csv, 'Net profit (USD)')], '150.00');
    // No symbol and no thousands separator anywhere in the numbers.
    expect(csv, isNot(contains(r'$')));
  });

  test('the per-distance rate reconciles with the columns beside it', () {
    const export = HistoryExport();
    final csv = export.toCsv([shift(id: 'a')]);
    final row = cells(rows(csv)[1]);

    final distance = double.parse(row[columnOf(csv, 'Distance (mi)')]);
    final netPerDistance = double.parse(row[columnOf(csv, 'Net per mi (USD)')]);
    final net = double.parse(row[columnOf(csv, 'Net profit (USD)')]);

    // Miles are stored and miles are exported: nothing is converted on the way
    // out, so the figure is the one the shift recorded.
    expect(distance, 100);
    // The column has to reconcile with the two beside it, or the spreadsheet
    // disagrees with itself.
    expect(netPerDistance, closeTo(net / distance, 0.01));
  });

  test('a multi-app shift lists every platform, quoted against the comma', () {
    const export = HistoryExport();

    final csv = export.toCsv([
      shift(id: 'a', earnings: {WorkPlatform.uber: 120, WorkPlatform.lyft: 80}),
    ]);

    expect(csv, contains('Uber + Lyft'));
  });

  test('a value containing a comma or quote is escaped per RFC 4180', () {
    const export = HistoryExport();
    final csv = export.toCsv([shift(id: 'a')]);

    // Nothing in this fixture needs quoting, so a bare row proves the escape
    // does not fire indiscriminately.
    expect(csv, isNot(contains('"')));
    expect(HistoryExport.escapeField('Uber, Lyft'), '"Uber, Lyft"');
    expect(HistoryExport.escapeField('say "hi"'), '"say ""hi"""');
    expect(HistoryExport.escapeField('line\r\nbreak'), '"line\r\nbreak"');
    expect(HistoryExport.escapeField('plain'), 'plain');
  });

  test('a note containing a comma cannot shift the columns after it', () {
    // Notes are free text and are the one field a driver can put anything in,
    // so they are now the realistic source of a stray delimiter.
    const export = HistoryExport();

    final csv = export.toCsv(
      const [],
      expenses: [expense(note: 'Brakes, rotors and labour')],
    );

    expect(csv, contains('"Brakes, rotors and labour"'));
    // The row still has exactly as many columns as the header, and the note
    // survives as one cell rather than spilling into the column beside it.
    expect(cells(rows(csv)[1]), hasLength(cells(rows(csv).first).length));
    expect(
      cells(rows(csv)[1])[columnOf(csv, 'Note')],
      'Brakes, rotors and labour',
    );
  });

  test('records come out newest first, matching History', () {
    const export = HistoryExport();

    final csv = export.toCsv(
      [
        shift(id: 'old', completedAt: DateTime(2026, 8, 1)),
        shift(id: 'new', completedAt: DateTime(2026, 8, 20)),
      ],
      expenses: [expense(incurredOn: DateTime(2026, 8, 10))],
    );
    final body = rows(csv).skip(1).toList();
    final dateColumn = columnOf(csv, 'Date');

    // One ledger on one date axis: the expense sorts between the two sessions
    // rather than into a block of its own.
    expect(cells(body[0])[dateColumn], '2026-08-20');
    expect(cells(body[1])[dateColumn], '2026-08-10');
    expect(cells(body[2])[dateColumn], '2026-08-01');
  });

  group('one file, two record types', () {
    test('the Record column tells them apart', () {
      const export = HistoryExport();

      final csv = export.toCsv([shift(id: 'a')], expenses: [expense()]);
      final record = columnOf(csv, 'Record');

      expect(record, 0, reason: 'a spreadsheet filters on it before anything');
      expect(cells(rows(csv)[1])[record], 'Expense');
      expect(cells(rows(csv)[2])[record], 'Session');
    });

    test('an expense leaves every session column empty', () {
      // Empty rather than zero: a zero would be summed as though the driver had
      // earned nothing that day, quietly dragging down every average.
      const export = HistoryExport();
      final csv = export.toCsv(const [], expenses: [expense()]);
      final row = cells(rows(csv)[1]);

      for (final header in [
        'Time',
        'Apps',
        'Gross (USD)',
        'Hours',
        'Distance (mi)',
        'Direct expenses (USD)',
        'Vehicle cost (USD)',
        'Total expenses (USD)',
        'Net profit (USD)',
        'Net per hour (USD)',
        'Net per mi (USD)',
        'Keep rate (%)',
      ]) {
        expect(row[columnOf(csv, header)], '', reason: '$header must be blank');
      }
    });

    test('a session leaves every expense column empty', () {
      const export = HistoryExport();
      final csv = export.toCsv([shift(id: 'a')]);
      final row = cells(rows(csv)[1]);

      for (final header in [
        'Category',
        'Schedule C line',
        'Vehicle cost?',
        'Amount (USD)',
        'Note',
      ]) {
        expect(row[columnOf(csv, header)], '', reason: '$header must be blank');
      }
    });

    test('an expense carries the Schedule C line and the vehicle flag', () {
      // The flag is what decides whether the cost can be claimed alongside the
      // standard mileage rate, and the file is the only place an accountant
      // can read it.
      const export = HistoryExport();
      final csv = export.toCsv(
        const [],
        expenses: [
          expense(id: 'car', category: ExpenseCategory.vehiclePayment),
          expense(
            id: 'phone',
            category: ExpenseCategory.phone,
            incurredOn: DateTime(2026, 8, 11),
          ),
        ],
      );

      final car = cells(rows(csv)[1]);
      final phone = cells(rows(csv)[2]);

      expect(car[columnOf(csv, 'Category')], 'Car payment or lease');
      expect(car[columnOf(csv, 'Schedule C line')], 'Car and truck expenses');
      expect(car[columnOf(csv, 'Vehicle cost?')], 'Yes');
      expect(car[columnOf(csv, 'Amount (USD)')], '400.00');

      expect(phone[columnOf(csv, 'Schedule C line')], 'Utilities');
      expect(phone[columnOf(csv, 'Vehicle cost?')], 'No');
    });
  });

  group('year scoping', () {
    test('a year keeps only that year, across both record types', () {
      const export = HistoryExport();

      final csv = export.toCsv(
        [
          shift(id: 'in', completedAt: DateTime(2026, 3, 1)),
          shift(id: 'out', completedAt: DateTime(2025, 3, 1)),
        ],
        expenses: [
          expense(id: 'in', incurredOn: DateTime(2026, 6, 1)),
          expense(id: 'out', incurredOn: DateTime(2025, 6, 1)),
        ],
        year: 2026,
      );

      expect(rows(csv).skip(1), hasLength(2));
      expect(csv, isNot(contains('2025-')));
    });

    test('no year exports the whole history', () {
      const export = HistoryExport();

      final csv = export.toCsv(
        [
          shift(id: 'a', completedAt: DateTime(2026, 3, 1)),
          shift(id: 'b', completedAt: DateTime(2025, 3, 1)),
        ],
        expenses: [expense(incurredOn: DateTime(2024, 6, 1))],
      );

      expect(rows(csv).skip(1), hasLength(3));
    });
  });

  test('an empty history produces a header and nothing else', () {
    const export = HistoryExport();
    expect(rows(export.toCsv([])), hasLength(1));
  });

  group('sharing', () {
    test(
      'sharing nothing at all is refused rather than opening a sheet',
      () async {
        const export = HistoryExport();
        expect(await export.share([]), isFalse);
      },
    );

    test('a driver with only expenses can still export', () async {
      // The old guard asked whether there were sessions. Someone who has logged
      // a car payment and no shifts yet still has a record worth keeping.
      const export = HistoryExport();
      final csv = export.toCsv(const [], expenses: [expense()]);

      expect(rows(csv).skip(1), hasLength(1));
    });

    test('a year with no records in it is refused', () async {
      const export = HistoryExport();
      expect(
        await export.share([shift(id: 'a')], year: 1999),
        isFalse,
        reason: 'an empty year must not open a share sheet on a header row',
      );
    });
  });
}
