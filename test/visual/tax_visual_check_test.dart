// Renders the Taxes tab and the expense surfaces to PNGs so they can be looked
// at rather than inferred from a passing assertion.
//
//   flutter test test/visual/tax_visual_check_test.dart --update-goldens
//
// The figures are checked in the unit tests; this exists to catch what those
// cannot — overflow, label collisions, and a comparison card that reads wrong.
@Tags(['visual'])
library;

import 'dart:io';

import 'package:driver_wealth_os/core/theme/app_theme.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/settings/domain/driving_costs.dart';
import 'package:driver_wealth_os/features/settings/domain/measurement_units.dart';
import 'package:driver_wealth_os/features/settings/presentation/settings_screen.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/tax/domain/expense.dart';
import 'package:driver_wealth_os/features/tax/presentation/expense_editor_sheet.dart';
import 'package:driver_wealth_os/features/tax/presentation/tax_year_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadRealFonts() async {
  // Without this the test renderer draws every glyph as a filled box, which
  // hides exactly the collisions this check is for.
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  Future<void> load(String family, Map<String, String> faces) async {
    final loader = FontLoader(family);
    var any = false;
    for (final entry in faces.entries) {
      final file = File('${dir.path}/${entry.value}');
      if (!file.existsSync()) continue;
      any = true;
      loader.addFont(
        file.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
      );
    }
    if (any) await loader.load();
  }

  await load('Roboto', {
    'regular': 'Roboto-Regular.ttf',
    'medium': 'Roboto-Medium.ttf',
    'bold': 'Roboto-Bold.ttf',
    'black': 'Roboto-Black.ttf',
  });
  await load('MaterialIcons', {'regular': 'MaterialIcons-Regular.otf'});
}

/// A fixed year so the screenshots do not change meaning in January.
DateTime _clock() => DateTime(2026, 8, 30, 9);

void main() {
  setUpAll(_loadRealFonts);

  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget child, {
    Brightness brightness = Brightness.light,
    Size size = const Size(400, 900),
    double scrollBy = 0,
    Key? tap,
    // Applied before [tap], for a control that starts below the fold.
    double scrollToReach = 0,
  }) async {
    const dpr = 2.0;
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: child,
      ),
    );
    await tester.pumpAndSettle();
    if (scrollToReach != 0) {
      await tester.drag(find.byType(ListView).first, Offset(0, -scrollToReach));
      await tester.pumpAndSettle();
    }
    if (tap != null) {
      await tester.tap(find.byKey(tap));
      await tester.pumpAndSettle();
    }
    if (scrollBy != 0) {
      await tester.drag(find.byType(ListView).first, Offset(0, -scrollBy));
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/$name.png'),
    );
  }

  Shift shift(String id, {double miles = 120, double gross = 320}) =>
      Shift.single(
        id: id,
        platform: WorkPlatform.uber,
        gross: gross,
        hours: 7,
        miles: miles,
        directExpenses: 24,
        vehicleCostPerMile: .20,
        completedAt: DateTime(2026, 8, 20),
      );

  List<Shift> seedShifts() => [for (var i = 0; i < 40; i++) shift('s$i')];

  List<Expense> seedExpenses() => [
    Expense(
      id: 'e1',
      amount: 420,
      category: ExpenseCategory.vehiclePayment,
      incurredOn: DateTime(2026, 8, 1),
      note: 'August payment',
    ),
    Expense(
      id: 'e2',
      amount: 138.4,
      category: ExpenseCategory.insurance,
      incurredOn: DateTime(2026, 7, 15),
    ),
    Expense(
      id: 'e3',
      amount: 64.99,
      category: ExpenseCategory.phone,
      incurredOn: DateTime(2026, 8, 5),
      note: 'Unlimited data',
    ),
    Expense(
      id: 'e4',
      amount: 289.5,
      category: ExpenseCategory.maintenance,
      incurredOn: DateTime(2026, 6, 2),
      note: 'Brakes and rotors',
    ),
    Expense(
      id: 'e5',
      amount: 31.2,
      category: ExpenseCategory.supplies,
      incurredOn: DateTime(2026, 8, 22),
    ),
  ];

  Widget taxScreen({List<Shift>? shifts, List<Expense>? expenses}) =>
      TaxYearScreen(
        shifts: shifts ?? seedShifts(),
        expenses: expenses ?? seedExpenses(),
        units: const MeasurementUnits(),
        clock: _clock,
        onExpenseAdded: (_) {},
        onExpenseUpdated: (_) {},
        onExpenseDeleted: (_) {},
      );

  Widget settings({List<Expense>? expenses}) => SettingsScreen(
    driverName: 'Ahmed',
    shifts: seedShifts(),
    expenses: expenses ?? seedExpenses(),
    onOpenTaxes: () {},
    dailyGoal: 250,
    drivingCosts: const DrivingCosts(),
    hourlyFloor: 25,
    weekStartsOn: DateTime.monday,
    drivingDaysPerWeek: 5,
    units: const MeasurementUnits(),
    onDriverNameChanged: (_) {},
    onDailyGoalChanged: (_) {},
    onVehicleCostPerMileChanged: (_) {},
    onEnergySourceChanged: (_) {},
    onFuelEfficiencyChanged: (_) {},
    onFuelPriceChanged: (_) {},
    onHourlyFloorChanged: (_) {},
    onWeekStartsOnChanged: (_) {},
    onDrivingDaysPerWeekChanged: (_) {},
    themeMode: ThemeMode.system,
    onThemeModeChanged: (_) {},
    onExportData: () async {},
    onOpenPrivacy: () {},
  );

  testWidgets('tax year light', (tester) async {
    await capture(tester, 'tax_year_light', taxScreen());
  });

  testWidgets('tax year dark', (tester) async {
    await capture(
      tester,
      'tax_year_dark',
      taxScreen(),
      brightness: Brightness.dark,
    );
  });

  testWidgets('tax year expense list', (tester) async {
    await capture(tester, 'tax_year_expenses', taxScreen(), scrollBy: 620);
  });

  testWidgets('tax year empty', (tester) async {
    await capture(
      tester,
      'tax_year_empty',
      taxScreen(shifts: const [], expenses: const []),
    );
  });

  // Few miles against a big car payment, so actual expenses carry the year and
  // the comparison card has to say the opposite of the default case.
  testWidgets('tax year actual expenses win', (tester) async {
    await capture(
      tester,
      'tax_year_actual_wins',
      taxScreen(shifts: [shift('s1', miles: 40)]),
    );
  });

  testWidgets('expense editor', (tester) async {
    await capture(
      tester,
      'expense_editor',
      Scaffold(
        body: ExpenseEditorSheet(
          units: const MeasurementUnits(),
          today: _clock,
          initialCategory: ExpenseCategory.vehiclePayment,
        ),
      ),
    );
  });

  // Taxes makes five tabs. Captured at 360pt — a small handset — because that
  // is where five labels either fit or start truncating.
  testWidgets('navigation bar with five tabs', (tester) async {
    await capture(
      tester,
      'nav_five_tabs',
      Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 3,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded),
              label: 'Coach',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Taxes',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
      size: const Size(360, 300),
    );
  });

  // The receipt slot is the one control that asks the driver to photograph a
  // document with their card number on it, so the reassurance beside it has to
  // be legible rather than buried.
  testWidgets('expense editor with a receipt attached', (tester) async {
    await capture(
      tester,
      'expense_editor_receipt',
      Scaffold(
        body: ExpenseEditorSheet(
          units: const MeasurementUnits(),
          today: _clock,
          initial: Expense(
            id: 'e1',
            amount: 289.5,
            category: ExpenseCategory.maintenance,
            incurredOn: DateTime(2026, 8, 17),
            note: 'Brakes and rotors',
            // A path that does not resolve, which is also the real case after
            // the OS clears the file: the row must still render.
            receiptPath: '/tmp/not-a-real-receipt.jpg',
          ),
        ),
      ),
    );
  });

  testWidgets('expense categories sheet', (tester) async {
    await capture(
      tester,
      'expense_categories_sheet',
      settings(),
      scrollToReach: 900,
      tap: const ValueKey('settings-expense-categories'),
    );
  });
}
