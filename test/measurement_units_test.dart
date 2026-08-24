import 'package:driver_wealth_os/features/settings/domain/measurement_units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Units are a display concern, so every one of these is really the same
/// question: can a driver switch to kilometres and back without their stored
/// figures moving? A conversion that is not exactly reversible would let a
/// round trip through Settings quietly rewrite what their car costs.
void main() {
  const imperial = MeasurementUnits();
  const metric = MeasurementUnits(distance: DistanceUnit.kilometres);

  group('distance', () {
    test('miles are the identity', () {
      expect(imperial.distance.fromMiles(120), 120);
      expect(imperial.distance.toMiles(120), 120);
    });

    test('a mile is exactly 1.609344 km', () {
      expect(metric.distance.fromMiles(1), closeTo(1.609344, 1e-9));
      expect(metric.distance.toMiles(1.609344), closeTo(1, 1e-9));
    });

    test('a round trip returns the original mileage', () {
      final there = metric.distance.fromMiles(137.4);
      expect(metric.distance.toMiles(there), closeTo(137.4, 1e-9));
    });
  });

  group('per-distance rates', () {
    test('the same money over more units is less per unit', () {
      // $0.30/mi spread over the 1.609 km in a mile.
      expect(metric.rateFromPerMile(0.30), closeTo(0.186411, 1e-6));
      expect(imperial.rateFromPerMile(0.30), 0.30);
    });

    test('a round trip returns the original rate', () {
      final shown = metric.rateFromPerMile(0.4237);
      expect(metric.rateToPerMile(shown), closeTo(0.4237, 1e-9));
    });
  });

  group('fuel efficiency', () {
    test('25 MPG is 10.63 km per litre', () {
      // 25 mi/gal × 1.609344 km/mi ÷ 3.785411784 L/gal.
      expect(
        metric.efficiencyFromStored(25, electric: false),
        closeTo(10.6286, 1e-4),
      );
    });

    test('an EV converts distance only, because kWh is kWh everywhere', () {
      expect(
        metric.efficiencyFromStored(3.5, electric: true),
        closeTo(3.5 * 1.609344, 1e-9),
      );
      expect(imperial.efficiencyFromStored(3.5, electric: true), 3.5);
    });

    test('a round trip returns the original figure, gas or electric', () {
      for (final electric in [true, false]) {
        final shown = metric.efficiencyFromStored(27.3, electric: electric);
        expect(
          metric.efficiencyToStored(shown, electric: electric),
          closeTo(27.3, 1e-9),
          reason: 'electric: $electric',
        );
      }
    });
  });

  group('fuel price', () {
    test('a gallon of fuel at \$3.50 is \$0.92 a litre', () {
      expect(
        metric.fuelPriceFromStored(3.50, electric: false),
        closeTo(0.9246, 1e-4),
      );
    });

    test('an EV price is per kWh in both systems', () {
      expect(metric.fuelPriceFromStored(0.17, electric: true), 0.17);
    });

    test('a round trip returns the original price', () {
      final shown = metric.fuelPriceFromStored(4.19, electric: false);
      expect(
        metric.fuelPriceToStored(shown, electric: false),
        closeTo(4.19, 1e-9),
      );
    });
  });

  group('volume follows distance', () {
    test('so nobody is ever asked for kilometres per gallon', () {
      expect(DistanceUnit.miles.volume, VolumeUnit.gallons);
      expect(DistanceUnit.kilometres.volume, VolumeUnit.litres);
    });
  });

  group('labels', () {
    test('name the driver\'s own units', () {
      expect(imperial.efficiencyLabel(electric: false), 'Miles per gallon');
      expect(metric.efficiencyLabel(electric: false), 'Kilometres per litre');
      expect(metric.efficiencyLabel(electric: true), 'Kilometres per kWh');
      expect(metric.fuelPriceLabel(electric: false), 'Price per litre');
      expect(imperial.rateLabel(0.30), r'$0.30/mi');
      expect(metric.distanceLabel(100), '160.9 km');
    });

    test('carry the chosen currency, not a hardcoded dollar', () {
      const pounds = MeasurementUnits(currency: SupportedCurrency.gbp);
      expect(pounds.rateLabel(0.30), '£0.30/mi');
    });
  });

  group('decoding a stored preference', () {
    test('falls back rather than throwing on an unknown value', () {
      expect(DistanceUnit.fromName('furlongs'), DistanceUnit.miles);
      expect(DistanceUnit.fromName(null), DistanceUnit.miles);
      expect(SupportedCurrency.fromCode('XYZ'), SupportedCurrency.usd);
      expect(SupportedCurrency.fromCode('GBP'), SupportedCurrency.gbp);
    });
  });
}
