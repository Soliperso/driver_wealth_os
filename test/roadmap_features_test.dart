import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation adapts between compact and wide layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(1024, 900);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('weekly, DNA and coach are reachable end to end', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', shifts: _patternShifts()),
    );
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('This week'), findsOneWidget);
    // History does not carry a second copy of the pattern grid.
    expect(find.text('Earnings DNA'), findsNothing);

    await tester.tap(find.text('Coach'));
    await tester.pumpAndSettle();
    expect(find.text('Profit coach'), findsOneWidget);

    // Earnings DNA is reached through Coach's ranked-patterns card, which is
    // the app's one route to this reading.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coach-best-times')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible stops as soon as the finder matches, which can leave
    // the card still under the floating bottom bar and the tap missing it.
    await tester.ensureVisible(find.byKey(const ValueKey('coach-best-times')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach-best-times')));
    await tester.pumpAndSettle();

    expect(find.text('Best times'), findsOneWidget);
    expect(find.text('Earnings DNA'), findsOneWidget);
    // Grades appear both in the heatmap cells and in the ranked list.
    expect(find.text('A'), findsWidgets);
    expect(find.text('D'), findsWidgets);
  });
}

List<Shift> _patternShifts() {
  final now = DateTime.now();
  return [
    _shift('a', now, 7, 50),
    _shift('b', now, 12, 40),
    _shift('c', now, 18, 30),
    _shift('d', now, 23, 20),
  ];
}

Shift _shift(String id, DateTime day, int hour, double profit) => Shift.single(
  id: id,
  platform: WorkPlatform.uber,
  gross: profit,
  hours: 1,
  miles: 0,
  directExpenses: 0,
  vehicleCostPerMile: 0,
  completedAt: DateTime(day.year, day.month, day.day, hour),
);
