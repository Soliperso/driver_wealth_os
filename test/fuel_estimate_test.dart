import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/settings/domain/driving_costs.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/shifts/presentation/add_shift_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The regression suite for a bug that made the app's headline number wrong.
///
/// Settings and onboarding both collected fuel economy and fuel price, and
/// onboarding told the driver "every mile you drive costs you $0.44". Nothing
/// ever read those figures back: `Shift.vehicleCost` used the wear rate alone,
/// so the fuel half of the cost model never reached a profit figure and every
/// shift was overstated by the price of its own fuel.
void main() {
  const costs = DrivingCosts(
    // 20 MPG at $4.00/gal is exactly $0.20 a mile, so the arithmetic below can
    // be checked by eye.
    fuelEfficiency: 20,
    fuelPrice: 4,
    vehicleCostPerMile: .30,
  );

  Future<void> pump(
    WidgetTester tester, {
    Shift? initialShift,
    bool isNewFromSession = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: AddShiftScreen(
        onSave: (_) {},
        drivingCosts: costs,
        initialShift: initialShift,
        isNewFromSession: isNewFromSession,
      ),
    ),
  );

  Finder expensesField() => find.ancestor(
    of: find.text('Fuel, tolls & parking'),
    matching: find.byType(TextFormField),
  );

  test('the cost model prices a mile as fuel plus wear', () {
    expect(costs.fuelCostPerMile, .20);
    expect(costs.allInCostPerMile, .50);
    expect(costs.estimatedFuel(100), 20);
  });

  testWidgets('typing miles estimates the fuel they burned', (tester) async {
    await pump(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Miles driven'),
      '100',
    );
    await tester.pump();

    expect(find.widgetWithText(TextFormField, '20.00'), findsOneWidget);
    expect(
      find.textContaining(r'$20.00 estimated fuel at 20 mi/gal at $4.00/gal'),
      findsOneWidget,
    );
  });

  testWidgets('a tracked shift is costed before the driver types anything', (
    tester,
  ) async {
    // Hours and miles were measured by the phone; only the money is missing.
    final tracked = Shift.single(
      id: 'tracked-1',
      platform: WorkPlatform.uber,
      gross: 0,
      hours: 4,
      miles: 150,
      directExpenses: 0,
      vehicleCostPerMile: .30,
      completedAt: DateTime(2026, 8, 18, 19),
    );

    await pump(tester, initialShift: tracked, isNewFromSession: true);

    expect(find.widgetWithText(TextFormField, '30.00'), findsOneWidget);
  });

  testWidgets('the estimate never overwrites a figure the driver typed', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Miles driven'),
      '100',
    );
    await tester.pump();
    expect(find.widgetWithText(TextFormField, '20.00'), findsOneWidget);

    // A real receipt: fuel plus a toll.
    await tester.enterText(expensesField(), '27.50');
    await tester.pump();

    // Correcting the mileage must not throw that away.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Miles driven'),
      '120',
    );
    await tester.pump();

    expect(find.widgetWithText(TextFormField, '27.50'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '24.00'), findsNothing);
  });

  testWidgets('editing a saved shift leaves its costs alone', (tester) async {
    final saved = Shift.single(
      id: 'saved-1',
      platform: WorkPlatform.uber,
      gross: 200,
      hours: 5,
      miles: 100,
      // Deliberately not what the current rates would estimate.
      directExpenses: 6.25,
      vehicleCostPerMile: .30,
      completedAt: DateTime(2026, 8, 18, 19),
    );

    await pump(tester, initialShift: saved);

    expect(find.widgetWithText(TextFormField, '6.25'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '20.00'), findsNothing);
  });

  testWidgets('the estimate reaches the saved shift s true profit', (
    tester,
  ) async {
    Shift? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: AddShiftScreen(
          onSave: (shift) => saved = shift,
          drivingCosts: costs,
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Gross earnings'),
      '200',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hours online'),
      '5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Miles driven'),
      '100',
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    // $200 gross, $20 fuel over 100 miles, $30 wear at $0.30/mi.
    // Before this fix the fuel line was $0 and the driver was told $170.
    expect(saved!.directExpenses, 20);
    expect(saved!.vehicleCost, 30);
    expect(saved!.netProfit, 150);
  });

  testWidgets('the form names miles, and stores exactly what was typed', (
    tester,
  ) async {
    Shift? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: AddShiftScreen(
          onSave: (shift) => saved = shift,
          drivingCosts: costs,
        ),
      ),
    );

    // The app is miles everywhere, so the field says so and the number in it
    // is the number that gets stored — there is no conversion step to get
    // wrong.
    expect(find.text('Miles driven'), findsOneWidget);
    expect(find.text('Vehicle wear per mile'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Gross earnings'),
      '200',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hours online'),
      '5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Miles driven'),
      '100',
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    expect(saved!.miles, 100);
    expect(saved!.vehicleCostPerMile, closeTo(.30, .0001));
    expect(saved!.directExpenses, closeTo(20, .01));
  });

  testWidgets('a driver who has not set an economy sees no estimate', (
    tester,
  ) async {
    // Zero efficiency means fuel is excluded rather than infinite — a shift
    // must not be wiped out by a blank setting.
    await tester.pumpWidget(
      MaterialApp(
        home: AddShiftScreen(
          onSave: (_) {},
          drivingCosts: const DrivingCosts(fuelEfficiency: 0),
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Miles driven'),
      '100',
    );
    await tester.pump();

    expect(find.textContaining('estimated fuel'), findsNothing);
  });
}
