import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/tax/domain/expense.dart';
import 'package:driver_wealth_os/features/tax/domain/mileage_rate.dart';
import 'package:driver_wealth_os/features/tax/domain/quarterly_estimate.dart';
import 'package:driver_wealth_os/features/tax/domain/tax_year_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rates verified against the IRS "Standard mileage rates" table on
/// 21 August 2026: https://www.irs.gov/tax-professionals/standard-mileage-rates
void main() {
  Shift shift(
    String id,
    DateTime on, {
    double gross = 200,
    double hours = 5,
    double miles = 100,
    double directExpenses = 0,
    double vehicleCostPerMile = 0,
  }) => Shift.single(
    id: id,
    platform: WorkPlatform.uber,
    gross: gross,
    hours: hours,
    miles: miles,
    directExpenses: directExpenses,
    vehicleCostPerMile: vehicleCostPerMile,
    completedAt: on,
  );

  group('MileageRates', () {
    test('prices a shift at the rate in force on its own day', () {
      expect(MileageRates.bandFor(DateTime(2025, 6, 1))!.centsPerMile, 70);
      expect(MileageRates.bandFor(DateTime(2024, 6, 1))!.centsPerMile, 67);
      expect(MileageRates.bandFor(DateTime(2023, 6, 1))!.centsPerMile, 65.5);
    });

    test('honours the mid-year change the IRS made in 2026', () {
      // The reason rates are date-banded rather than keyed by year. A
      // year-keyed table would deduct one of these rates for both halves.
      expect(MileageRates.bandFor(DateTime(2026, 6, 30))!.centsPerMile, 72.5);
      expect(MileageRates.bandFor(DateTime(2026, 7, 1))!.centsPerMile, 76);
      // Late on the last day of June is still June.
      expect(
        MileageRates.bandFor(DateTime(2026, 6, 30, 23, 59))!.centsPerMile,
        72.5,
      );
    });

    test('honours the mid-year change the IRS made in 2022', () {
      expect(MileageRates.bandFor(DateTime(2022, 6, 30))!.centsPerMile, 58.5);
      expect(MileageRates.bandFor(DateTime(2022, 7, 1))!.centsPerMile, 62.5);
    });

    test('refuses to price a year it has no published rate for', () {
      // No guess and no extrapolation: a made-up rate here becomes a made-up
      // number on a tax return.
      expect(MileageRates.bandFor(DateTime(2027, 1, 1)), isNull);
      expect(MileageRates.deductionFor(DateTime(2027, 1, 1), 100), isNull);
      expect(MileageRates.bandFor(DateTime(2021, 12, 31)), isNull);
    });

    test('a mid-year-change year reports both of its bands', () {
      expect(MileageRates.bandsForYear(2026), hasLength(2));
      expect(MileageRates.bandsForYear(2025), hasLength(1));
    });

    test('deducts miles at the published rate', () {
      expect(MileageRates.deductionFor(DateTime(2025, 3, 1), 100), 70);
      expect(MileageRates.deductionFor(DateTime(2026, 8, 1), 100), 76);
      expect(MileageRates.deductionFor(DateTime(2026, 2, 1), 100), 72.5);
    });
  });

  group('TaxYearSummary', () {
    test('accumulates the deduction across a mid-year rate change', () {
      final summary = TaxYearSummary.from(
        year: 2026,
        shifts: [
          // 100 miles at 72.5¢ = $72.50
          shift('a', DateTime(2026, 3, 10)),
          // 100 miles at 76¢ = $76.00
          shift('b', DateTime(2026, 8, 10)),
        ],
      );

      expect(summary.deductibleMiles, 200);
      expect(summary.standardMileageDeduction, 148.50);
      // A single blended annual rate would have produced 200 × 0.7425 = $148.50
      // here by coincidence of the even split; the per-shift accumulation is
      // what makes an uneven year correct.
      expect(summary.rateBands, hasLength(2));
    });

    test('an uneven split is not the same as a blended rate', () {
      final summary = TaxYearSummary.from(
        year: 2026,
        shifts: [
          shift('a', DateTime(2026, 3, 10), miles: 1000),
          shift('b', DateTime(2026, 8, 10), miles: 100),
        ],
      );

      // 1000 × .725 + 100 × .76 = 725 + 76
      expect(summary.standardMileageDeduction, 801);
      // Averaging the two rates would have given 1100 × .7425 = $816.75.
      expect(summary.standardMileageDeduction, isNot(816.75));
    });

    test('picks the larger of standard mileage and actual expenses', () {
      // A cheap, efficient car: the standard rate beats real costs.
      final efficient = TaxYearSummary.from(
        year: 2025,
        shifts: [
          shift(
            'a',
            DateTime(2025, 3, 10),
            miles: 1000,
            directExpenses: 100,
            vehicleCostPerMile: .10,
          ),
        ],
      );
      // Standard: 1000 × .70 = $700. Actual: $100 + $100 = $200.
      expect(efficient.standardMileageDeduction, 700);
      expect(efficient.vehicleExpenses, 200);
      expect(efficient.betterMethod, DeductionMethod.standardMileage);
      expect(efficient.betterVehicleDeduction, 700);
      expect(efficient.methodAdvantage, 500);

      // A thirsty car with a big repair bill: actual costs win.
      final thirsty = TaxYearSummary.from(
        year: 2025,
        shifts: [
          shift(
            'a',
            DateTime(2025, 3, 10),
            miles: 1000,
            directExpenses: 400,
            vehicleCostPerMile: .50,
          ),
        ],
        expenses: [
          Expense(
            id: 'e1',
            amount: 1200,
            category: ExpenseCategory.maintenance,
            incurredOn: DateTime(2025, 5, 2),
          ),
        ],
      );
      // Actual: $400 + $500 + $1200 = $2100 against $700 standard.
      expect(thirsty.vehicleExpenses, 2100);
      expect(thirsty.betterMethod, DeductionMethod.actualExpenses);
      expect(thirsty.betterVehicleDeduction, 2100);
    });

    test('non-vehicle costs are claimable alongside either method', () {
      final summary = TaxYearSummary.from(
        year: 2025,
        shifts: [shift('a', DateTime(2025, 3, 10), miles: 1000)],
        expenses: [
          Expense(
            id: 'phone',
            amount: 300,
            category: ExpenseCategory.phone,
            incurredOn: DateTime(2025, 4, 1),
          ),
          Expense(
            id: 'fees',
            amount: 150,
            category: ExpenseCategory.platformFees,
            incurredOn: DateTime(2025, 4, 1),
          ),
        ],
      );

      expect(summary.otherExpenses, 450);
      // The phone bill does not compete with the mileage rate — it is added on
      // top of whichever vehicle method wins.
      expect(summary.totalDeductions, 700 + 450);
    });

    test('vehicle costs never land on the non-vehicle side', () {
      // The flag that prevents double-counting a cost the standard rate
      // already covers.
      for (final category in ExpenseCategory.values) {
        final summary = TaxYearSummary.from(
          year: 2025,
          shifts: const [],
          expenses: [
            Expense(
              id: 'e',
              amount: 100,
              category: category,
              incurredOn: DateTime(2025, 4, 1),
            ),
          ],
        );
        if (category.isVehicleCost) {
          expect(summary.vehicleExpenses, 100, reason: category.name);
          expect(summary.otherExpenses, 0, reason: category.name);
        } else {
          expect(summary.otherExpenses, 100, reason: category.name);
          expect(summary.vehicleExpenses, 0, reason: category.name);
        }
      }
    });

    test('flags driving it could not price rather than dropping it', () {
      final summary = TaxYearSummary.from(
        year: 2027,
        shifts: [shift('a', DateTime(2027, 3, 10), miles: 500)],
      );

      expect(summary.unratedMiles, 500);
      expect(summary.deductibleMiles, 0);
      expect(summary.standardMileageDeduction, 0);
      // The driver is told the figure is incomplete rather than shown a low
      // total with no explanation.
      expect(summary.isProvisional, isTrue);
    });

    test('ignores records outside the year and duplicate ids', () {
      final summary = TaxYearSummary.from(
        year: 2025,
        shifts: [
          shift('a', DateTime(2025, 3, 10)),
          shift('a', DateTime(2025, 3, 10)),
          shift('b', DateTime(2024, 3, 10)),
        ],
      );

      expect(summary.shiftCount, 1);
      expect(summary.deductibleMiles, 100);
    });

    test('reports the years the driver has records in, newest first', () {
      expect(
        TaxYearSummary.yearsCovered(
          shifts: [
            shift('a', DateTime(2024, 3, 10)),
            shift('b', DateTime(2026, 3, 10)),
          ],
          expenses: [
            Expense(
              id: 'e',
              amount: 10,
              category: ExpenseCategory.phone,
              incurredOn: DateTime(2025, 1, 1),
            ),
          ],
        ),
        [2026, 2025, 2024],
      );
    });
  });

  group('quarterly estimates', () {
    test('the IRS quarters are not three months each', () {
      final quarters = TaxQuarters.forYear(2026);

      expect(quarters[0].periodEnd, DateTime(2026, 3, 31));
      expect(quarters[0].dueDate, DateTime(2026, 4, 15));
      // Q2 covers two months, not three.
      expect(quarters[1].periodStart, DateTime(2026, 4, 1));
      expect(quarters[1].periodEnd, DateTime(2026, 5, 31));
      expect(quarters[1].dueDate, DateTime(2026, 6, 15));
      expect(quarters[2].dueDate, DateTime(2026, 9, 15));
      // The one that catches people out: Q4 is due in the new year.
      expect(quarters[3].dueDate, DateTime(2027, 1, 15));
    });

    test('names the next payment due', () {
      expect(TaxQuarters.nextDue(DateTime(2026, 8, 21))!.number, 3);
      expect(TaxQuarters.nextDue(DateTime(2026, 4, 1))!.number, 1);
      // After Q3's due date the next one is Q4, due the following January.
      expect(TaxQuarters.nextDue(DateTime(2026, 10, 1))!.number, 4);
    });

    test('sets aside a share of profit and never a share of a loss', () {
      expect(SetAside.of(1000, rate: .25).amount, 250);
      expect(SetAside.of(1000, rate: .3).amount, 300);
      // A losing quarter owes nothing, and a negative set-aside is not a
      // refund.
      expect(SetAside.of(-500).amount, 0);
      expect(SetAside.of(0).amount, 0);
    });

    test('an out-of-range rate cannot produce a nonsense figure', () {
      expect(SetAside.of(1000, rate: 5).amount, 1000);
      expect(SetAside.of(1000, rate: -1).amount, 0);
      expect(SetAside.of(1000, rate: double.nan).amount, 0);
    });
  });
}
