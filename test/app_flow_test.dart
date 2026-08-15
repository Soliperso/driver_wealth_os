import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/features/accounts/application/earnings_connection_gateway.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/accounts/presentation/work_accounts_screen.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/shifts/presentation/add_shift_screen.dart';
import 'package:driver_wealth_os/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('onboarding opens the Today dashboard', (tester) async {
    await tester.pumpWidget(const DriverWealthApp());
    expect(find.text('Drive smarter.\nKeep more.'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Ahmed');
    final continueButton = find.text('Continue');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(find.text('TRUE PROFIT'), findsOneWidget);
    expect(find.text('Enter a shift manually'), findsOneWidget);
  });

  testWidgets('work account flow lists supported platforms', (tester) async {
    await tester.pumpWidget(const DriverWealthApp());
    await tester.enterText(find.byType(EditableText), 'Ahmed');
    final continueButton = find.text('Continue');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    // Work accounts live in Settings only; Today no longer advertises them.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    // Settings is a lazy ListView, so the card has to be scrolled to before it
    // exists in the tree at all.
    final connectButton = find.byKey(const ValueKey('settings-work-accounts'));
    await tester.scrollUntilVisible(
      connectButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible stops as soon as the finder matches, and the
    // ListView's cache extent builds the card while it is still off-screen.
    await tester.ensureVisible(connectButton);
    await tester.pumpAndSettle();
    await tester.tap(connectButton);
    await tester.pumpAndSettle();

    expect(find.text('Work accounts'), findsOneWidget);
    expect(find.text('Uber'), findsOneWidget);
    expect(find.text('Lyft'), findsOneWidget);
    expect(find.text('DoorDash'), findsOneWidget);
    expect(find.text('Instacart'), findsOneWidget);
    expect(find.byKey(const ValueKey('platform-logo-uber')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('platform-logo-amazon_flex')),
      findsOneWidget,
    );
  });

  testWidgets('daily goal can be edited from the dashboard', (tester) async {
    await tester.pumpWidget(const DriverWealthApp());
    await tester.enterText(find.byType(EditableText), 'Ahmed');
    final continueButton = find.text('Continue');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Daily goal'));
    await tester.pumpAndSettle();
    expect(find.text('Daily profit goal'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '325');
    await tester.tap(find.text('Save goal'));
    await tester.pumpAndSettle();

    expect(find.text(r'$0 / $325'), findsOneWidget);
  });

  testWidgets('successful work account connection shows connected status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WorkAccountsScreen(connectionGateway: _ConnectedGateway()),
      ),
    );

    final uberRow = find.ancestor(
      of: find.text('Uber'),
      matching: find.byType(InkWell),
    );
    await tester.tap(uberRow);
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('manual shift menu includes every supported platform', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: AddShiftScreen(onSave: (_) {})));

    await tester.tap(find.byType(DropdownButtonFormField<WorkPlatform>));
    await tester.pumpAndSettle();

    for (final platform in WorkPlatform.values) {
      expect(find.text(platform.displayName), findsWidgets);
    }
  });

  testWidgets('daily goal changes to exceeded state', (tester) async {
    final shift = Shift.single(
      id: 'goal-test',
      platform: WorkPlatform.uber,
      gross: 310,
      hours: 8,
      miles: 20,
      directExpenses: 0,
      vehicleCostPerMile: .25,
      completedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          driverName: 'Ahmed',
          shifts: [shift],
          dailyGoal: 300,
          onAddShift: _doNothing,
          onDailyGoalChanged: _ignoreGoal,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('daily-goal-state-exceeded')),
      findsOneWidget,
    );
    expect(find.text(r'Goal exceeded by $5.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shift-platform-logo-goal-test')),
      200,
    );
    expect(
      find.byKey(const ValueKey('shift-platform-logo-goal-test')),
      findsOneWidget,
    );
  });

  testWidgets('daily goal changes to reached state', (tester) async {
    final shift = Shift.single(
      id: 'goal-reached-test',
      platform: WorkPlatform.lyft,
      gross: 305,
      hours: 8,
      miles: 20,
      directExpenses: 0,
      vehicleCostPerMile: .25,
      completedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TodayScreen(
          driverName: 'Ahmed',
          shifts: [shift],
          dailyGoal: 300,
          onAddShift: _doNothing,
          onDailyGoalChanged: _ignoreGoal,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('daily-goal-state-reached')),
      findsOneWidget,
    );
    expect(find.text('Daily goal reached'), findsOneWidget);
  });

  testWidgets('manual shift saves once and returns to dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(const DriverWealthApp());
    await tester.enterText(find.byType(EditableText), 'Ahmed');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter a shift manually'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '300');
    await tester.enterText(fields.at(1), '8');
    await tester.enterText(fields.at(2), '100');
    await tester.enterText(fields.at(3), '20');
    await tester.enterText(fields.at(4), '.30');
    await tester.ensureVisible(find.text('Calculate true profit'));
    await tester.tap(find.text('Calculate true profit'));
    await tester.pumpAndSettle();

    expect(find.text(r'$250.00'), findsWidgets);
    await tester.ensureVisible(find.text('Save to Today'));
    await tester.tap(find.text('Save to Today'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Recent shifts'), 200);
    expect(find.text('Recent shifts'), findsOneWidget);
    // Scrolled to on its own rather than assumed to be near the heading: the
    // rows below it sit outside the viewport and are not built until reached.
    final manualLogo = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'shift-platform-logo-manual-',
          ),
    );
    await tester.scrollUntilVisible(manualLogo, 200);
    expect(manualLogo, findsOneWidget);
  });
}

void _doNothing() {}

void _ignoreGoal(double _) {}

final class _ConnectedGateway implements EarningsConnectionGateway {
  const _ConnectedGateway();

  @override
  Future<ConnectionLaunchResult> connect(WorkPlatform platform) async {
    return ConnectionLaunchResult.connected;
  }
}
