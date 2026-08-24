import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/history/presentation/history_analytics_sections.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Solo Uber: gross 120, costs 10 + (20mi × .20) = 14, net 106 over 2h → $53/hr.
Shift soloUber(String id) => Shift.single(
  id: id,
  platform: WorkPlatform.uber,
  gross: 120,
  hours: 2,
  miles: 20,
  directExpenses: 10,
  vehicleCostPerMile: .20,
  completedAt: DateTime(2026, 8, 10),
);

/// Solo Lyft: gross 100, same costs, net 86 over 2h → $43/hr.
Shift soloLyft(String id) => Shift.single(
  id: id,
  platform: WorkPlatform.lyft,
  gross: 100,
  hours: 2,
  miles: 20,
  directExpenses: 10,
  vehicleCostPerMile: .20,
  completedAt: DateTime(2026, 8, 10),
);

/// Uber and Lyft together: $150 and $50 of one shared 5-hour, 50-mile shift.
///
/// Folded into Uber it would drag Uber's rate from $53/hr to about $44.67 —
/// which is the misattribution these tests exist to catch.
Shift multiApp(String id) => Shift(
  id: id,
  earnings: {WorkPlatform.uber: 150, WorkPlatform.lyft: 50},
  hours: 5,
  miles: 50,
  directExpenses: 0,
  vehicleCostPerMile: .20,
  completedAt: DateTime(2026, 8, 11),
);

Future<void> pumpSection(WidgetTester tester, List<Shift> shifts) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlatformPerformanceSection(shifts: shifts),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a shared shift never lands on one platform’s ledger', (
    tester,
  ) async {
    await pumpSection(tester, [
      soloUber('uber-1'),
      soloUber('uber-2'),
      soloLyft('lyft-1'),
      soloLyft('lyft-2'),
      multiApp('both-1'),
    ]);

    // Each rate is exactly what the single-app shifts alone produce. If the
    // multi-app shift were grouped under its dominant platform, Uber would
    // read $44.67/hr here and would also be carrying Lyft's $50.
    expect(find.text(r'$53.00/hr'), findsOneWidget);
    expect(find.text(r'$43.00/hr'), findsOneWidget);
    expect(find.text(r'$44.67/hr'), findsNothing);

    // And the shift is not silently dropped either — it is reported separately.
    expect(find.byKey(const ValueKey('multi-app-split')), findsOneWidget);
  });

  testWidgets(
    'the head-to-head counts only single-app shifts toward its gate',
    (tester) async {
      // Two platforms are present, but only through shifts that ran both at
      // once. Nothing here can support a net-per-hour ranking.
      await pumpSection(tester, [multiApp('both-1'), multiApp('both-2')]);

      expect(
        find.byKey(const ValueKey('platform-comparison-learning')),
        findsOneWidget,
      );
      expect(find.text('0 of 2 platforms · 0 of 4 sessions'), findsOneWidget);
      expect(find.textContaining('the hours belong to both'), findsOneWidget);
      // The evidence they do have is still shown rather than withheld.
      expect(find.byKey(const ValueKey('multi-app-split')), findsOneWidget);
    },
  );

  testWidgets('the split reports each app’s share of the shared gross', (
    tester,
  ) async {
    await pumpSection(tester, [multiApp('both-1')]);

    expect(find.byKey(const ValueKey('multi-app-share-uber')), findsOneWidget);
    expect(find.byKey(const ValueKey('multi-app-share-lyft')), findsOneWidget);
    expect(find.text(r'$150.00'), findsOneWidget);
    expect(find.text(r'$50.00'), findsOneWidget);
    expect(find.text('75% of gross'), findsOneWidget);
    expect(find.text('25% of gross'), findsOneWidget);

    // No profit figure is offered for a shift whose costs cannot be split.
    expect(find.textContaining('/hr'), findsNothing);
    expect(find.textContaining('no per-app profit to compare'), findsOneWidget);
  });

  testWidgets('an unreviewed multi-app shift still reports its split', (
    tester,
  ) async {
    // Share of gross does not depend on fuel and tolls being confirmed, so
    // gating it behind a cost review would hide a figure that is already known.
    final unreviewed = Shift(
      id: 'imported-both',
      earnings: {WorkPlatform.uber: 150, WorkPlatform.lyft: 50},
      hours: 5,
      miles: 50,
      directExpenses: 0,
      vehicleCostPerMile: .20,
      completedAt: DateTime(2026, 8, 11),
      source: ShiftSource.imported,
      costsReviewed: false,
    );

    await pumpSection(tester, [unreviewed]);

    expect(find.byKey(const ValueKey('multi-app-split')), findsOneWidget);
    expect(find.text('75% of gross'), findsOneWidget);
  });

  testWidgets('a driver who never multi-apps sees no split at all', (
    tester,
  ) async {
    await pumpSection(tester, [
      soloUber('uber-1'),
      soloUber('uber-2'),
      soloLyft('lyft-1'),
      soloLyft('lyft-2'),
    ]);

    expect(find.byKey(const ValueKey('multi-app-split')), findsNothing);
    expect(find.text(r'$53.00/hr'), findsOneWidget);
    expect(find.text(r'$43.00/hr'), findsOneWidget);
  });
}
