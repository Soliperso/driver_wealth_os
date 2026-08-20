import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/settings/domain/distance_unit.dart';
import 'package:driver_wealth_os/features/settings/domain/driving_costs.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('persisted snapshots written before imports existed', () {
    // AppSnapshot.fromJson drops any shift whose parse throws, so a newly
    // required field would silently erase a driver's history on upgrade.
    test('load with every shift intact and default to manual', () {
      final legacy = {
        'driverName': 'Ahmed',
        'dailyGoal': 300.0,
        'shifts': [
          {
            'id': 'legacy-1',
            'platform': 'uber',
            'gross': 300.0,
            'hours': 8.0,
            'miles': 100.0,
            'directExpenses': 20.0,
            'vehicleCostPerMile': .30,
            'completedAt': DateTime(2026, 3, 2, 18).toIso8601String(),
          },
          {
            'id': 'legacy-2',
            'platform': 'lyft',
            'gross': 120.0,
            'hours': 4.0,
            'miles': 40.0,
            'directExpenses': 5.0,
            'vehicleCostPerMile': .30,
            'completedAt': DateTime(2026, 3, 3, 11).toIso8601String(),
          },
        ],
      };

      final restored = AppSnapshot.fromJson(legacy);

      expect(restored.shifts, hasLength(2));
      expect(
        restored.shifts.every((shift) => shift.source == ShiftSource.manual),
        isTrue,
      );
      expect(restored.driverName, 'Ahmed');
      expect(restored.dailyGoal, 300);
    });

    test('fall back to the shipped vehicle rate when the key is absent', () {
      final restored = AppSnapshot.fromJson({'driverName': 'Ahmed'});

      expect(
        restored.vehicleCostPerMile,
        AppSnapshot.defaultVehicleCostPerMile,
      );
    });
  });

  test('vehicle rate survives a save and reload round trip', () {
    final restored = AppSnapshot.fromJson(
      const AppSnapshot(driverName: 'Ahmed', vehicleCostPerMile: .42).toJson(),
    );

    expect(restored.vehicleCostPerMile, .42);
  });

  test('all calculation preferences survive a snapshot round trip', () {
    final restored = AppSnapshot.fromJson(
      const AppSnapshot(
        driverName: 'Ahmed',
        energySource: EnergySource.electric,
        fuelEfficiency: 3.8,
        fuelPrice: .19,
        hourlyFloor: 31,
        weekStartsOn: DateTime.sunday,
        drivingDaysPerWeek: 4,
        distanceUnit: DistanceUnit.kilometers,
        themeMode: ThemeMode.dark,
      ).toJson(),
    );

    expect(restored.energySource, EnergySource.electric);
    expect(restored.fuelEfficiency, 3.8);
    expect(restored.fuelPrice, .19);
    expect(restored.hourlyFloor, 31);
    expect(restored.weekStartsOn, DateTime.sunday);
    expect(restored.drivingDaysPerWeek, 4);
    expect(restored.distanceUnit, DistanceUnit.kilometers);
    expect(restored.themeMode, ThemeMode.dark);
  });

  test(
    'an out-of-range vehicle rate falls back instead of corrupting math',
    () {
      final restored = AppSnapshot.fromJson({
        'driverName': 'Ahmed',
        'vehicleCostPerMile': -5,
      });

      expect(
        restored.vehicleCostPerMile,
        AppSnapshot.defaultVehicleCostPerMile,
      );
    },
  );

  testWidgets('settings auto-save the goal and vehicle rate', (tester) async {
    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-save')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-daily-goal')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-daily-goal-field')),
      '325',
    );
    await tester.tap(find.byKey(const ValueKey('settings-editor-done')));
    await tester.pumpAndSettle();

    final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
    page.position.jumpTo(420);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-vehicle-rate')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-vehicle-rate-field')),
      '0.42',
    );
    await tester.tap(find.byKey(const ValueKey('settings-editor-done')));
    await tester.pumpAndSettle();

    expect(store.snapshot.dailyGoal, 325);
    expect(store.snapshot.vehicleCostPerMile, .42);
    expect(store.snapshot.driverName, 'Ahmed');
  });

  testWidgets('a new shift is seeded with the saved vehicle rate', (
    tester,
  ) async {
    final store = MemoryAppStore(
      const AppSnapshot(driverName: 'Ahmed', vehicleCostPerMile: .55),
    );
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter a shift manually'));
    await tester.pumpAndSettle();

    final rateField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Vehicle wear per mile'),
    );
    expect(rateField.controller?.text, '0.55');
  });
}
