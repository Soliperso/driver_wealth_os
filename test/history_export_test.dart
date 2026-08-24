import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/settings/application/history_export.dart';
import 'package:driver_wealth_os/features/settings/domain/measurement_units.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter_test/flutter_test.dart';

/// The export is the one place a driver's history leaves the app, so the file
/// has to be something a spreadsheet can actually add up — and it has to agree
/// with the figures the app showed them.
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

  List<String> rows(String csv) => csv.split('\r\n');
  List<String> cells(String row) => row.split(',');

  test('the header names the driver\'s units and currency', () {
    const export = HistoryExport(
      units: MeasurementUnits(
        distance: DistanceUnit.kilometres,
        currency: SupportedCurrency.gbp,
      ),
    );

    final header = rows(export.toCsv([shift(id: 'a')])).first;

    expect(header, contains('Distance (km)'));
    expect(header, contains('Gross (GBP)'));
    expect(header, contains('Net per km (GBP)'));
    expect(header, isNot(contains('(mi)')));
  });

  test('money is written unformatted so a spreadsheet can sum it', () {
    const export = HistoryExport();

    final row = cells(rows(export.toCsv([shift(id: 'a')]))[1]);

    // gross 200, direct 20, vehicle 100 * .30 = 30, net 150.
    expect(row[3], '200.00');
    expect(row[6], '20.00');
    expect(row[7], '30.00');
    expect(row[9], '150.00');
    // No symbol and no thousands separator anywhere in the numbers.
    expect(export.toCsv([shift(id: 'a')]), isNot(contains(r'$')));
  });

  test('distance is converted, and the per-distance rate matches it', () {
    const export = HistoryExport(
      units: MeasurementUnits(distance: DistanceUnit.kilometres),
    );

    final row = cells(rows(export.toCsv([shift(id: 'a')]))[1]);
    final distance = double.parse(row[5]);
    final netPerDistance = double.parse(row[11]);
    final net = double.parse(row[9]);

    expect(distance, closeTo(160.9, 0.1));
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

  test('shifts come out newest first, matching History', () {
    const export = HistoryExport();

    final csv = export.toCsv([
      shift(id: 'old', completedAt: DateTime(2026, 8, 1)),
      shift(id: 'new', completedAt: DateTime(2026, 8, 20)),
    ]);
    final body = rows(csv).skip(1).toList();

    expect(cells(body[0])[0], '2026-08-20');
    expect(cells(body[1])[0], '2026-08-01');
  });

  test('an empty history produces a header and nothing else', () {
    const export = HistoryExport();
    expect(rows(export.toCsv([])), hasLength(1));
  });

  test(
    'sharing an empty history is refused rather than opening a sheet',
    () async {
      const export = HistoryExport();
      expect(await export.share([]), isFalse);
    },
  );
}
