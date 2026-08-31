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
import 'package:driver_wealth_os/features/admin/application/admin_repository.dart';
import 'package:driver_wealth_os/features/admin/domain/admin_models.dart';
import 'package:driver_wealth_os/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:driver_wealth_os/features/coach/presentation/best_times_screen.dart';
import 'package:driver_wealth_os/features/coach/presentation/coach_screen.dart';
import 'package:driver_wealth_os/features/driving/domain/driving_session.dart';
import 'package:driver_wealth_os/features/history/presentation/history_analytics_sections.dart';
import 'package:driver_wealth_os/features/history/presentation/history_screen.dart';
import 'package:driver_wealth_os/features/settings/domain/measurement_units.dart';
import 'package:driver_wealth_os/features/settings/domain/driver_preferences.dart';
// Both libraries declare a `DistanceUnit`; this file already uses the stored
// one, so the display-side library is brought in for its units type only.
import 'package:driver_wealth_os/features/settings/domain/measurement_units.dart'
    show MeasurementUnits;
import 'package:driver_wealth_os/features/shifts/domain/shift_analytics.dart';
import 'package:driver_wealth_os/features/settings/domain/driving_costs.dart';
import 'package:driver_wealth_os/features/settings/presentation/settings_screen.dart';
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
    Key? tap,
    Key? tapInside,
    double tapAtFraction = .5,
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
    if (tap != null) {
      await tester.tap(find.byKey(tap));
      await tester.pumpAndSettle();
    }
    // For hit areas with no widget of their own to tap — a bar inside a
    // painted plot is addressed by position, not by key.
    if (tapInside != null) {
      final box = tester.getRect(find.byKey(tapInside));
      await tester.tapAt(
        Offset(box.left + box.width * tapAtFraction, box.center.dy),
      );
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

  testWidgets('settings light', (tester) async {
    await capture(tester, 'settings_light', _settings());
  });

  testWidgets('settings dark', (tester) async {
    await capture(
      tester,
      'settings_dark',
      _settings(),
      brightness: Brightness.dark,
    );
  });

  testWidgets('settings data and account', (tester) async {
    await capture(
      tester,
      'settings_data_account_dark',
      _settings(),
      brightness: Brightness.dark,
      scrollBy: 1150,
    );
  });

  // The hero card now carries the period selector, so the top of the screen is
  // the part worth looking at rather than something to scroll past.
  testWidgets('history light', (tester) async {
    await capture(tester, 'history_light', _history());
  });

  testWidgets('history dark', (tester) async {
    await capture(
      tester,
      'history_dark',
      _history(),
      brightness: Brightness.dark,
    );
  });

  // A window with nothing in it. The analytics stack is replaced by one card
  // pointing at where the sessions actually are, so this is the state to check
  // by eye: it is the whole screen below the hero.
  testWidgets('history empty period', (tester) async {
    await capture(tester, 'history_empty_period', _historyEmptyWeek());
  });

  testWidgets('history empty period dark', (tester) async {
    await capture(
      tester,
      'history_empty_period_dark',
      _historyEmptyWeek(),
      brightness: Brightness.dark,
    );
  });

  // Selecting a bucket paints a highlight behind the bar, which is easy to get
  // wrong: a full-slot grey wash reads as a rendering artefact rather than a
  // selection, so the selected state is checked on its own.
  testWidgets('history bar selected', (tester) async {
    await capture(
      tester,
      'history_bar_selected',
      _history(),
      brightness: Brightness.dark,
      tapInside: const ValueKey('period-profit-plot'),
      // Monday, the first of seven buckets.
      tapAtFraction: 1 / 14,
    );
  });

  // The line view has its own geometry — a curve, a gradient fill and the
  // value axis behind both — so it cannot be signed off from the bar golden.
  testWidgets('history line', (tester) async {
    await capture(
      tester,
      'history_line',
      _history(),
      tap: const ValueKey('chart-style-line'),
    );
  });

  // Thirty-one bars in the width of seven is the geometry most likely to
  // collide, so it gets its own capture.
  testWidgets('history month', (tester) async {
    await capture(
      tester,
      'history_month',
      _history(),
      tap: const ValueKey('period-month'),
      scrollBy: 300,
    );
  });

  // The cost split and the day-grouped shift list both live below the fold, so
  // neither is covered by the captures above.
  testWidgets('history cost breakdown', (tester) async {
    await capture(tester, 'history_breakdown', _history(), scrollBy: 620);
  });

  testWidgets('history shift list', (tester) async {
    await capture(
      tester,
      'history_shifts',
      _history(),
      brightness: Brightness.dark,
      scrollBy: 1750,
    );
  });

  // A shared session reports each app's share of the gross and no rate at all,
  // which is a different shape from the ranked head-to-head above it. Worth an
  // eye: it has to read as evidence rather than as a broken comparison.
  testWidgets('platform comparison multi-app split', (tester) async {
    await capture(
      tester,
      'platform_multi_app_split',
      Scaffold(body: SingleChildScrollView(child: _multiAppComparison())),
    );
  });

  // Earnings DNA now lives on Coach's Best times screen rather than being
  // drawn a second time on History, so the heatmap is captured there.
  testWidgets('earnings dna light', (tester) async {
    await capture(
      tester,
      'dna_light',
      BestTimesScreen(
        patterns: ShiftAnalytics.earningsPatterns(
          _seed().where((shift) => shift.hours > 0),
        ),
        units: const MeasurementUnits(),
      ),
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
        onDailyGoalChanged: (_) {},
        onStartDriving: () {},
        onEndShift: () async {},
        onPauseDriving: () async {},
        onResumeDriving: () async {},
        // Frozen so the golden is deterministic and the tree can settle.
        drivingRefreshInterval: null,
        drivingSession: DrivingSession.single(
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

  /// A shift running two apps, in dark mode.
  ///
  /// Dark is where the app tiles are hardest to read: several brand marks are
  /// near-black discs, and on a dark card they can disappear into it entirely.
  /// This is the case that has to keep being checked by eye.
  testWidgets('today driving multi app dark', (tester) async {
    await capture(
      tester,
      'today_driving_multi_app_dark',
      TodayScreen(
        driverName: 'Ahmed',
        shifts: _seed(),
        dailyGoal: 250,
        onAddShift: () {},
        onDailyGoalChanged: (_) {},
        onStartDriving: () {},
        onEndShift: () async {},
        onPauseDriving: () async {},
        onResumeDriving: () async {},
        // Both wired so the tiles render removable, with the add control
        // alongside them.
        onAddDrivingPlatform: () async {},
        onRemoveDrivingPlatform: (_) async {},
        drivingRefreshInterval: null,
        drivingSession: DrivingSession(
          id: 'preview',
          startedAt: DateTime.now().subtract(
            const Duration(hours: 1, minutes: 43, seconds: 17),
          ),
          platformSpans: [
            PlatformSpan(
              platform: WorkPlatform.uber,
              from: DateTime.now().subtract(const Duration(hours: 1)),
            ),
            PlatformSpan(
              platform: WorkPlatform.lyft,
              from: DateTime.now().subtract(const Duration(minutes: 30)),
            ),
          ],
          distanceMeters: 61800,
          vehicleCostPerMile: .35,
        ),
      ),
      brightness: Brightness.dark,
    );
  });

  testWidgets('today driving session paused', (tester) async {
    await capture(
      tester,
      'today_driving_paused',
      TodayScreen(
        driverName: 'Ahmed',
        shifts: _seed(),
        dailyGoal: 250,
        onAddShift: () {},
        onDailyGoalChanged: (_) {},
        onStartDriving: () {},
        onEndShift: () async {},
        onPauseDriving: () async {},
        onResumeDriving: () async {},
        drivingRefreshInterval: null,
        drivingSession: DrivingSession.single(
          id: 'preview',
          startedAt: DateTime.now().subtract(
            const Duration(hours: 2, minutes: 26, seconds: 17),
          ),
          platform: WorkPlatform.uber,
          distanceMeters: 61800,
          vehicleCostPerMile: .35,
          // Long enough to be carrying the warning, so the golden covers the
          // loudest form of the paused card rather than its quietest.
          pausedAt: DateTime.now().subtract(const Duration(minutes: 43)),
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

  // Coach is the screen with the most type ranks stacked down one scroll — an
  // eyebrow, a 40pt figure, a card title, a section heading and two body sizes
  // — so its rhythm is the thing a validator cannot sign off on.
  testWidgets('coach light', (tester) async {
    await capture(tester, 'coach_light', _coach());
  });

  testWidgets('coach dark', (tester) async {
    await capture(tester, 'coach_dark', _coach(), brightness: Brightness.dark);
  });

  // The chat card and the page footnote sit below the fold. Scrolled far
  // enough to show every suggested question, since the chip list is gated on
  // the data behind each one and is the part most likely to overflow.
  testWidgets('coach chat', (tester) async {
    await capture(tester, 'coach_chat', _coach(), scrollBy: 1250);
  });

  testWidgets('admin dashboard light', (tester) async {
    await capture(
      tester,
      'admin_dashboard_light',
      AdminDashboardScreen(repository: _PreviewAdminRepository()),
      size: const Size(430, 932),
    );
  });
}

/// Four solo sessions to rank, plus one shared session that cannot be ranked.
Widget _multiAppComparison() {
  Shift solo(String id, WorkPlatform platform, double gross) => Shift.single(
    id: id,
    platform: platform,
    gross: gross,
    hours: 5,
    miles: 60,
    directExpenses: 12,
    vehicleCostPerMile: .30,
    completedAt: DateTime(2026, 8, 10),
  );

  return PlatformPerformanceSection(
    shifts: [
      solo('u1', WorkPlatform.uber, 240),
      solo('u2', WorkPlatform.uber, 255),
      solo('l1', WorkPlatform.lyft, 190),
      solo('l2', WorkPlatform.lyft, 205),
      Shift(
        id: 'both',
        earnings: const {WorkPlatform.uber: 150, WorkPlatform.lyft: 50},
        hours: 5,
        miles: 50,
        directExpenses: 0,
        vehicleCostPerMile: .20,
        completedAt: DateTime(2026, 8, 11),
      ),
    ],
  );
}

Widget _settings() => SettingsScreen(
  driverName: 'Ahmed',
  shifts: const [],
  expenses: const [],
  onOpenTaxes: () {},
  dailyGoal: 100,
  drivingCosts: const DrivingCosts(
    energySource: EnergySource.gasoline,
    fuelEfficiency: 24.9,
    fuelPrice: 5.75,
    vehicleCostPerMile: .30,
  ),
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
  accountEmail: 'ahmed@example.com',
  onSignOut: () async {},
  onConnectAccounts: () {},
);

Widget _history() => HistoryScreen(
  shifts: _seed(),
  onAddShift: () {},
  onShiftUpdated: (_) {},
  onShiftDeleted: (_) {},
);

/// The same screen with every session pushed a fortnight back, so the window it
/// opens on — this week — is empty.
Widget _historyEmptyWeek() => HistoryScreen(
  shifts: [
    for (final shift in _seed())
      shift.copyWith(
        completedAt: shift.completedAt.subtract(const Duration(days: 14)),
      ),
  ],
  onAddShift: () {},
  onShiftUpdated: (_) {},
  onShiftDeleted: (_) {},
);

Widget _coach() => CoachScreen(
  shifts: _seed(),
  preferences: const DriverPreferences(driverName: 'Ahmed', dailyGoal: 250),
  onAddShift: () {},
);

Widget _today({required bool losing}) => TodayScreen(
  driverName: 'Ahmed',
  shifts: losing ? [_losingToday()] : _seed(),
  dailyGoal: 250,
  onAddShift: () {},
  onDailyGoalChanged: (_) {},
);

class _PreviewAdminRepository implements AdminRepository {
  @override
  Future<bool> canAccessAdmin() async => true;

  @override
  Future<AdminOverview> loadOverview() async => const AdminOverview(
    drivers: 128,
    activeDrivers: 119,
    shifts: 2846,
    connectedAccounts: 74,
    failedSyncs: 2,
    profit30Days: 186420,
  );

  @override
  Future<List<AdminUserSummary>> loadUsers({String query = ''}) async => [
    AdminUserSummary(
      id: 'one',
      email: 'taylor@example.com',
      driverName: 'Taylor',
      createdAt: DateTime.utc(2026, 7, 2),
      lastSignInAt: DateTime.utc(2026, 8, 14),
      cloudAccessEnabled: true,
      shiftCount: 84,
      totalProfit: 9420,
      workAccountCount: 2,
    ),
    AdminUserSummary(
      id: 'two',
      email: 'sam@example.com',
      driverName: 'Sam',
      createdAt: DateTime.utc(2026, 7, 18),
      lastSignInAt: DateTime.utc(2026, 8, 12),
      cloudAccessEnabled: false,
      shiftCount: 31,
      totalProfit: 3180,
      workAccountCount: 1,
    ),
  ];

  @override
  Future<void> setCloudAccess({
    required String userId,
    required bool enabled,
  }) async {}
}

Shift _losingToday() => Shift.single(
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
  ) => Shift.single(
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
