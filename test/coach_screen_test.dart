import 'package:driver_wealth_os/core/widgets/learning_progress.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/coach/presentation/coach_screen.dart';
import 'package:driver_wealth_os/features/settings/domain/driver_preferences.dart';
import 'package:driver_wealth_os/features/settings/domain/measurement_units.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('coach opens ranked best times from recorded patterns', (
    tester,
  ) async {
    await _pump(tester, shifts: _patterns());

    // The ranked-patterns card sits below the hero and the weekly reading, so
    // it is off-screen on a handset until scrolled to.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coach-best-times')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('coach-best-times')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach-best-times')));
    await tester.pumpAndSettle();

    expect(find.text('Best times'), findsOneWidget);
    expect(find.text('Your recorded patterns'), findsOneWidget);
    expect(find.text('True hourly'), findsWidgets);
  });

  testWidgets('suggested question renders a transparent local chat answer', (
    tester,
  ) async {
    await _pump(tester, shifts: _patterns());

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coach-question-0')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('coach-question-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach-question-0')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Simulated locally from saved sessions. No AI service is connected.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a driver with no history gets one empty state, not a wall of learning '
    'cards',
    (tester) async {
      await _pump(tester, shifts: const []);

      expect(find.byKey(const ValueKey('coach-empty')), findsOneWidget);
      expect(find.text('Nothing to coach yet'), findsOneWidget);
      // The four insight cards must not render at all: a page that says "not
      // yet" five times over is what this empty state replaced.
      expect(
        find.byKey(const ValueKey('coach-weekly-performance')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('coach-money-leak')), findsNothing);
      expect(find.byType(LearningProgress), findsNothing);
    },
  );

  testWidgets(
    'an insight that cannot conclude yet shows its progress, not a static chip',
    (tester) async {
      await _pump(tester, shifts: [_shift('one', DateTime.now(), 12, 140)]);

      // The chip reported no progress at all; the bar and its caption say how
      // much history the conclusion is still waiting on.
      expect(find.text('LEARNING'), findsNothing);
      expect(find.byType(LearningProgress), findsWidgets);
      expect(find.text('1 of 4 patterns tracked'), findsWidgets);
    },
  );

  testWidgets('money is grouped in the driver’s own currency', (tester) async {
    // The regression this covers: Coach hand-rolled `symbol + toStringAsFixed`,
    // so it printed £1234.56 while every other screen printed £1,234.56.
    final now = DateTime.now();
    await _pump(
      tester,
      // No costs, so the figure on screen is exactly the gross and the
      // assertion cannot drift with the vehicle-cost rate.
      shifts: [
        Shift.single(
          id: 'rich',
          platform: WorkPlatform.uber,
          gross: 1234.56,
          hours: 5,
          miles: 0,
          directExpenses: 0,
          vehicleCostPerMile: 0,
          completedAt: DateTime(now.year, now.month, now.day, 12),
        ),
      ],
      preferences: const DriverPreferences(
        driverName: 'Ahmed',
        dailyGoal: 250,
        units: MeasurementUnits(currency: SupportedCurrency.gbp),
      ),
    );

    expect(find.textContaining('£1,234.56'), findsWidgets);
    expect(find.textContaining('£1234.56'), findsNothing);
  });

  testWidgets('pull to refresh asks for fresh earnings', (tester) async {
    var refreshed = 0;
    await _pump(
      tester,
      shifts: _patterns(),
      onRefresh: () async => refreshed++,
    );

    await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
    await tester.pumpAndSettle();

    expect(refreshed, 1);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Shift> shifts,
  DriverPreferences preferences = const DriverPreferences(
    driverName: 'Ahmed',
    dailyGoal: 250,
  ),
  Future<void> Function()? onRefresh,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: CoachScreen(
        shifts: shifts,
        preferences: preferences,
        onRefresh: onRefresh,
        onAddShift: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Shift> _patterns() {
  final now = DateTime.now();
  return [
    _shift('a', now.subtract(const Duration(days: 1)), 7, 220),
    _shift('b', now.subtract(const Duration(days: 2)), 12, 180),
    _shift('c', now.subtract(const Duration(days: 3)), 18, 160),
    _shift('d', now.subtract(const Duration(days: 4)), 23, 140),
  ];
}

Shift _shift(String id, DateTime day, int hour, double gross) => Shift.single(
  id: id,
  platform: WorkPlatform.uber,
  gross: gross,
  hours: 5,
  miles: 40,
  directExpenses: 12,
  vehicleCostPerMile: .30,
  completedAt: DateTime(day.year, day.month, day.day, hour),
);
