import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
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

  testWidgets('settings persist the driver name, goal and vehicle rate', (
    tester,
  ) async {
    final store = MemoryAppStore(const AppSnapshot(driverName: 'Ahmed'));
    await tester.pumpWidget(DriverWealthApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('settings-daily-goal')),
      '325',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-vehicle-rate')),
      '0.42',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-save')),
      200,
      // The theme selector introduces a second Scrollable, so the page's own
      // list has to be named explicitly.
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('settings-save')));
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
