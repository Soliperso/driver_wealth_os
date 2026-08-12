// Renders the chart surfaces to PNGs so they can actually be looked at.
//
//   flutter test test/visual --update-goldens
//
// The colour system is validated computationally elsewhere; this exists to
// catch what a validator cannot — label collisions, geometry and overflow.
@Tags(['visual'])
library;

import 'dart:io';

import 'package:driver_wealth_os/core/theme/app_theme.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/driving/domain/driving_session.dart';
import 'package:driver_wealth_os/features/freedom/domain/freedom_goal.dart';
import 'package:driver_wealth_os/features/freedom/presentation/freedom_screen.dart';
import 'package:driver_wealth_os/features/history/presentation/history_screen.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadRealFonts() async {
  // Without this the test renderer draws every glyph as a filled box, which
  // hides exactly the label collisions this check is for.
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

void main() {
  setUpAll(_loadRealFonts);

  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget child, {
    Brightness brightness = Brightness.light,
    // Logical size; converted to physical below so the viewport matches a real
    // handset rather than a device half its width.
    Size size = const Size(400, 900),
    double scrollBy = 0,
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
    if (scrollBy != 0) {
      await tester.drag(find.byType(ListView).first, Offset(0, -scrollBy));
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/$name.png'),
    );
  }

  testWidgets('history light', (tester) async {
    await capture(tester, 'history_light', _history(), scrollBy: 120);
  });

  testWidgets('history dark', (tester) async {
    await capture(
      tester,
      'history_dark',
      _history(),
      brightness: Brightness.dark,
      scrollBy: 120,
    );
  });

  testWidgets('earnings dna light', (tester) async {
    await capture(tester, 'dna_light', _history(), scrollBy: 640);
  });

  testWidgets('freedom ring light', (tester) async {
    await capture(tester, 'freedom_light', _freedom());
  });

  testWidgets('freedom ring dark', (tester) async {
    await capture(
      tester,
      'freedom_dark',
      _freedom(),
      brightness: Brightness.dark,
    );
  });

  testWidgets('today idle with start driving', (tester) async {
    await capture(
      tester,
      'today_start_driving',
      TodayScreen(
        driverName: 'Ahmed',
        shifts: _seed(),
        dailyGoal: 250,
        onAddShift: () {},
        onConnectAccounts: () {},
        onDailyGoalChanged: (_) {},
        onStartDriving: () {},
      ),
    );
  });

  testWidgets('today driving session active', (tester) async {
    await capture(
      tester,
      'today_driving_active',
      TodayScreen(
        driverName: 'Ahmed',
        shifts: _seed(),
        dailyGoal: 250,
        onAddShift: () {},
        onConnectAccounts: () {},
        onDailyGoalChanged: (_) {},
        onStartDriving: () {},
        onEndShift: () async {},
        // Frozen so the golden is deterministic and the tree can settle.
        drivingRefreshInterval: null,
        drivingSession: DrivingSession(
          id: 'preview',
          startedAt: DateTime.now().subtract(
            const Duration(hours: 1, minutes: 43, seconds: 17),
          ),
          platform: WorkPlatform.uber,
          distanceMeters: 61800, // ~38.4 miles
          vehicleCostPerMile: .35,
        ),
      ),
    );
  });

  testWidgets('today loss light', (tester) async {
    await capture(tester, 'today_loss_light', _today(losing: true));
  });

  testWidgets('today profit dark', (tester) async {
    await capture(
      tester,
      'today_profit_dark',
      _today(losing: false),
      brightness: Brightness.dark,
    );
  });
}

Widget _history() => HistoryScreen(
  shifts: _seed(),
  onAddShift: () {},
  onShiftUpdated: (_) {},
  onShiftDeleted: (_) {},
);

Widget _freedom() => FreedomScreen(
  shifts: _seed(),
  goal: FreedomGoal(
    id: 'goal-1',
    title: 'Emergency fund',
    targetAmount: 5000,
    startingAmount: 500,
    allocationRate: .25,
    createdAt: DateTime(2026, 6, 1),
  ),
  onGoalChanged: (_) {},
);

Widget _today({required bool losing}) => TodayScreen(
  driverName: 'Ahmed',
  shifts: losing ? [_losingToday()] : _seed(),
  dailyGoal: 250,
  onAddShift: () {},
  onConnectAccounts: () {},
  onDailyGoalChanged: (_) {},
);

Shift _losingToday() => Shift(
  id: 'losing-today',
  platform: WorkPlatform.doorDash,
  gross: 60,
  hours: 5,
  miles: 210,
  directExpenses: 40,
  vehicleCostPerMile: .30,
  completedAt: DateTime.now(),
);

/// Fixed relative to "now" so the weekly chart always has a current week, with
/// a loss day, an idle day and an imported shift among them.
List<Shift> _seed() {
  final now = DateTime.now();
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));

  Shift make(
    String id,
    DateTime at,
    WorkPlatform platform,
    double gross,
    double hours,
    double miles,
    double expenses,
  ) => Shift(
    id: id,
    platform: platform,
    gross: gross,
    hours: hours,
    miles: miles,
    directExpenses: expenses,
    vehicleCostPerMile: .30,
    completedAt: at,
    source: id.startsWith('imported')
        ? ShiftSource.imported
        : ShiftSource.manual,
  );

  return [
    make(
      'cur-mon',
      monday.add(const Duration(hours: 19)),
      WorkPlatform.uber,
      280,
      8,
      120,
      25,
    ),
    make(
      'cur-tue',
      monday.add(const Duration(days: 1, hours: 13)),
      WorkPlatform.lyft,
      190,
      6,
      95,
      18,
    ),
    make(
      'cur-thu',
      monday.add(const Duration(days: 3, hours: 23)),
      WorkPlatform.doorDash,
      60,
      5,
      210,
      40,
    ),
    make(
      'imported-fri',
      monday.add(const Duration(days: 4, hours: 20)),
      WorkPlatform.uber,
      310,
      9,
      140,
      0,
    ),
    make(
      'prev-mon',
      monday.subtract(const Duration(days: 7)),
      WorkPlatform.uber,
      220,
      8,
      130,
      30,
    ),
    make(
      'prev-wed',
      monday.subtract(const Duration(days: 5)),
      WorkPlatform.lyft,
      260,
      8,
      110,
      22,
    ),
    make(
      'prev-fri',
      monday.subtract(const Duration(days: 3)),
      WorkPlatform.uber,
      300,
      9,
      150,
      28,
    ),
    make(
      'old-1',
      monday.subtract(const Duration(days: 10)),
      WorkPlatform.grubhub,
      210,
      6,
      90,
      18,
    ),
    make(
      'old-2',
      monday.subtract(const Duration(days: 12)),
      WorkPlatform.instacart,
      175,
      6,
      85,
      16,
    ),
    make(
      'old-3',
      monday.subtract(const Duration(days: 15)),
      WorkPlatform.amazonFlex,
      130,
      5,
      95,
      20,
    ),
  ];
}
