// Development-only entrypoint used to eyeball the charts with realistic data.
//
//   flutter run -t tool/preview_charts.dart -d macos
//
// Lives outside `lib/` because it is the only place in the repo that fabricates
// shift data, and nothing that ships should be able to import it by accident.
// `lib/main.dart` remains the app's entrypoint.
import 'package:flutter/material.dart';

import 'package:driver_wealth_os/core/theme/app_theme.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/freedom/domain/freedom_goal.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:driver_wealth_os/features/today/presentation/app_shell.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  var _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: Stack(
        children: [
          AppShell(
            driverName: 'Ahmed',
            shifts: _seedShifts(),
            dailyGoal: 250,
            vehicleCostPerMile: .30,
            freedomGoal: FreedomGoal(
              id: 'goal-1',
              title: 'Emergency fund',
              targetAmount: 5000,
              startingAmount: 500,
              allocationRate: .25,
              createdAt: DateTime.now().subtract(const Duration(days: 60)),
            ),
            onShiftAdded: (_) {},
            onShiftUpdated: (_) {},
            onShiftDeleted: (_) {},
            onDailyGoalChanged: (_) {},
            onVehicleCostPerMileChanged: (_) {},
            onDriverNameChanged: (_) {},
            onFreedomGoalChanged: (_) {},
            themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
            onThemeModeChanged: (mode) =>
                setState(() => _dark = mode == ThemeMode.dark),
          ),
          Positioned(
            right: 16,
            top: 44,
            child: FloatingActionButton.small(
              onPressed: () => setState(() => _dark = !_dark),
              child: const Icon(Icons.brightness_6_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

/// A month of shifts across several platforms, including a losing day and an
/// idle day, so every visual state shows up at once.
List<Shift> _seedShifts() {
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
    // Current week — Monday to today, with Thursday a loss and Wednesday idle.
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
      'imported-cur-fri',
      monday.add(const Duration(days: 4, hours: 20)),
      WorkPlatform.uber,
      310,
      9,
      140,
      0,
    ),
    make(
      'cur-sat',
      monday.add(const Duration(days: 5, hours: 2)),
      WorkPlatform.instacart,
      240,
      7,
      88,
      20,
    ),

    // Prior week, for the ghost comparison.
    make(
      'prev-mon',
      monday.subtract(const Duration(days: 7 - 0, hours: -18)),
      WorkPlatform.uber,
      220,
      8,
      130,
      30,
    ),
    make(
      'prev-wed',
      monday.subtract(const Duration(days: 5, hours: -12)),
      WorkPlatform.lyft,
      260,
      8,
      110,
      22,
    ),
    make(
      'prev-fri',
      monday.subtract(const Duration(days: 3, hours: -21)),
      WorkPlatform.uber,
      300,
      9,
      150,
      28,
    ),
    make(
      'prev-sun',
      monday.subtract(const Duration(days: 1, hours: -9)),
      WorkPlatform.grubhub,
      150,
      5,
      70,
      15,
    ),

    // Older history so Earnings DNA has enough distinct patterns to grade.
    make(
      'old-1',
      monday.subtract(const Duration(days: 10, hours: -8)),
      WorkPlatform.uber,
      210,
      6,
      90,
      18,
    ),
    make(
      'old-2',
      monday.subtract(const Duration(days: 12, hours: -14)),
      WorkPlatform.lyft,
      175,
      6,
      85,
      16,
    ),
    make(
      'old-3',
      monday.subtract(const Duration(days: 15, hours: -23)),
      WorkPlatform.doorDash,
      130,
      5,
      95,
      20,
    ),
    make(
      'old-4',
      monday.subtract(const Duration(days: 18, hours: -3)),
      WorkPlatform.amazonFlex,
      200,
      7,
      100,
      19,
    ),
    make(
      'old-5',
      monday.subtract(const Duration(days: 21, hours: -19)),
      WorkPlatform.uber,
      260,
      8,
      115,
      24,
    ),
  ];
}
