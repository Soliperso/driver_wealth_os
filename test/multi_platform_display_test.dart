import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/accounts/presentation/platform_logo.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Shift multiApp() => Shift(
  id: 'manual-both',
  earnings: {WorkPlatform.uber: 150, WorkPlatform.lyft: 50},
  hours: 5,
  miles: 50,
  directExpenses: 10,
  vehicleCostPerMile: .20,
  completedAt: DateTime(2026, 8, 11, 20),
);

Shift soloApp() => Shift.single(
  id: 'manual-solo',
  platform: WorkPlatform.doorDash,
  gross: 120,
  hours: 2,
  miles: 20,
  directExpenses: 10,
  vehicleCostPerMile: .20,
  completedAt: DateTime(2026, 8, 10, 20),
);

/// A Wednesday in the same week as both fixtures above (that week runs Mon 10th
/// to Sun 16th), so History's default "this week" window contains them.
///
/// Pinned rather than left to `DateTime.now()`: History anchors its period on
/// the wall clock, so without this these tests only passed during the week they
/// were written and failed silently from the following Monday onwards.
DateTime clock() => DateTime(2026, 8, 12, 12);

void main() {
  testWidgets('a shift row names every app it ran, not just the biggest', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', shifts: [multiApp(), soloApp()]),
    );

    await tester.pumpWidget(KeeprateApp(store: store, clock: clock));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('history-shift-manual-both'));
    await tester.scrollUntilVisible(row, 200);

    // Named for both, and the row's logo cluster carries both marks.
    expect(find.text('Uber + Lyft'), findsWidgets);
    final cluster = tester.widget<PlatformLogoCluster>(
      find.descendant(of: row, matching: find.byType(PlatformLogoCluster)),
    );
    expect(cluster.platforms, [WorkPlatform.uber, WorkPlatform.lyft]);

    // A single-app shift is untouched by any of this. Scrolled to explicitly:
    // History builds its day groups lazily, so a row below the fold is not in
    // the tree to be found.
    final solo = find.byKey(const ValueKey('history-shift-manual-solo'));
    await tester.scrollUntilVisible(solo, 200);
    expect(
      find.descendant(of: solo, matching: find.text('DoorDash')),
      findsOneWidget,
    );
  });

  testWidgets('shift detail itemises what each app paid', (tester) async {
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', shifts: [multiApp()]),
    );

    await tester.pumpWidget(KeeprateApp(store: store, clock: clock));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('history-shift-manual-both'));
    await tester.scrollUntilVisible(row, 200);
    await Scrollable.ensureVisible(tester.element(row), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Session details'), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-earnings-uber')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-earnings-lyft')), findsOneWidget);
    expect(find.text(r'$150.00'), findsWidgets);
    expect(find.text(r'$50.00'), findsWidgets);
    // The total is labelled as such once it is a sum of the lines above it.
    expect(find.text('Gross earnings (total)'), findsOneWidget);

    // Costs stay whole — they were spent once, by one car — so there is no
    // per-app fuel or vehicle line pretending otherwise.
    expect(find.text('Fuel, tolls & parking'), findsOneWidget);
    expect(find.text('Vehicle wear'), findsOneWidget);
  });

  testWidgets('a single-app shift detail shows no per-app breakdown', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', shifts: [soloApp()]),
    );

    await tester.pumpWidget(KeeprateApp(store: store, clock: clock));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('history-shift-manual-solo'));
    await tester.scrollUntilVisible(row, 200);
    await Scrollable.ensureVisible(tester.element(row), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('detail-earnings-doordash')),
      findsNothing,
    );
    expect(find.text('Gross earnings'), findsOneWidget);
    expect(find.text('Gross earnings (total)'), findsNothing);
  });
}
