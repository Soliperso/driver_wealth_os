import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/settings/domain/measurement_units.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The regression suite for a promise the app made and did not keep.
///
/// `README` advertised multi-currency display, and Settings honoured the
/// preference — but Today, the History hero, shift detail and the driving hero
/// all called `Money`, which was pinned to `en_US` and a literal `$`. A driver
/// who chose GBP and kilometres saw £/km in Settings and $/mi on every screen
/// they actually used.
void main() {
  DateTime clock() => DateTime(2026, 8, 12, 20);

  Shift shift() => Shift.single(
    id: 'gbp-1',
    platform: WorkPlatform.uber,
    gross: 200,
    hours: 5,
    // 160.9344 km.
    miles: 100,
    directExpenses: 20,
    vehicleCostPerMile: .30,
    completedAt: DateTime(2026, 8, 12, 18),
  );

  AppSnapshot metricSnapshot() => AppSnapshot(
    driverName: 'Ahmed',
    dailyGoal: 250,
    distanceUnit: DistanceUnit.kilometres,
    currency: SupportedCurrency.gbp,
    shifts: [shift()],
  );

  testWidgets('Today shows the driver s own currency and distance unit', (
    tester,
  ) async {
    await tester.pumpWidget(
      DriverWealthApp(
        store: MemoryAppStore(metricSnapshot()),
        clock: clock,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    // £150 net: £200 gross − £20 direct − £30 wear.
    expect(find.textContaining('£'), findsWidgets);
    expect(find.textContaining(r'$'), findsNothing);

    // The performance panel names the driver's unit rather than "Net/mile".
    await tester.scrollUntilVisible(find.text('Net/km'), 200);
    expect(find.text('Net/km'), findsOneWidget);
    expect(find.text('Kilometres'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('History and shift detail follow the same preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      DriverWealthApp(
        store: MemoryAppStore(metricSnapshot()),
        clock: clock,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.textContaining(r'$'), findsNothing);
    // The hero's six supporting figures follow the unit too. Its tiles render
    // their labels in caps.
    expect(find.text('NET / KM'), findsOneWidget);
    expect(find.text('KILOMETRES'), findsOneWidget);

    final row = find.byKey(const ValueKey('history-shift-gbp-1'));
    await tester.scrollUntilVisible(row, 200);
    await Scrollable.ensureVisible(tester.element(row), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Session details'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
    // 100 miles rendered as kilometres.
    expect(find.textContaining('161 km'), findsOneWidget);
    expect(find.text('Net / kilometre'), findsOneWidget);
  });

  testWidgets('a US driver still sees dollars and miles', (tester) async {
    await tester.pumpWidget(
      DriverWealthApp(
        store: MemoryAppStore(
          AppSnapshot(driverName: 'Ahmed', dailyGoal: 250, shifts: [shift()]),
        ),
        clock: clock,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(r'$'), findsWidgets);
    expect(find.textContaining('£'), findsNothing);
    await tester.scrollUntilVisible(find.text('Net/mi'), 200);
    expect(find.text('Net/mi'), findsOneWidget);
    expect(find.text('Miles'), findsOneWidget);
  });
}
