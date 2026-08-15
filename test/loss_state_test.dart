import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a day that lost money gets its own state, not a quiet zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          driverName: 'Ahmed',
          shifts: [_losingShift()],
          dailyGoal: 250,
          onAddShift: _doNothing,
          onDailyGoalChanged: _ignoreGoal,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('daily-goal-state-loss')), findsOneWidget);
    expect(find.text('You spent more than you earned'), findsOneWidget);
    // Minus sign leads the amount; the old formatting put it after the
    // currency symbol, which reads as a typo on the screen that matters most.
    expect(find.text(r'-$40.00'), findsOneWidget);

    // The coaching line has its own branch for a losing day rather than
    // falling through to "you're $X from today's goal".
    await tester.scrollUntilVisible(
      find.textContaining('cost \$40.00 more than it earned'),
      200,
    );
    expect(
      find.textContaining('cost \$40.00 more than it earned'),
      findsOneWidget,
    );
  });

  testWidgets('an empty day shows no keep rate rather than zero percent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          driverName: 'Ahmed',
          shifts: const [],
          dailyGoal: 250,
          onAddShift: _doNothing,
          onDailyGoalChanged: _ignoreGoal,
        ),
      ),
    );

    expect(find.text('— kept'), findsOneWidget);
    expect(find.text('0% kept'), findsNothing);
    expect(
      find.byKey(const ValueKey('daily-goal-state-noActivity')),
      findsOneWidget,
    );
  });

  testWidgets('recent shifts show even when nothing was driven today', (
    tester,
  ) async {
    final lastWeek = Shift.single(
      id: 'older-1',
      platform: WorkPlatform.lyft,
      gross: 200,
      hours: 6,
      miles: 80,
      directExpenses: 10,
      vehicleCostPerMile: .30,
      completedAt: DateTime.now().subtract(const Duration(days: 7)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          driverName: 'Ahmed',
          shifts: [lastWeek],
          dailyGoal: 250,
          onAddShift: _doNothing,
          onDailyGoalChanged: _ignoreGoal,
        ),
      ),
    );

    // Previously this section was gated on having driven *today*, so a driver
    // with history but an idle day saw no recent shifts at all.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shift-platform-logo-older-1')),
      200,
    );
    expect(find.text('Recent shifts'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shift-platform-logo-older-1')),
      findsOneWidget,
    );
  });
}

Shift _losingShift() => Shift.single(
  id: 'losing-1',
  platform: WorkPlatform.uber,
  gross: 50,
  hours: 4,
  miles: 200,
  directExpenses: 30,
  vehicleCostPerMile: .30,
  completedAt: DateTime.now(),
);

void _doNothing() {}

void _ignoreGoal(double _) {}
