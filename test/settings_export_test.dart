import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/settings/application/shift_export.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV export includes financial totals and one row per shift', () {
    final shift = Shift.single(
      id: 'shift-1',
      platform: WorkPlatform.uber,
      gross: 100,
      hours: 4,
      miles: 50,
      directExpenses: 10,
      vehicleCostPerMile: .30,
      completedAt: DateTime(2026, 8, 20, 18, 30),
      source: ShiftSource.manual,
    );

    final csv = ShiftExport.csv([shift]);

    expect(csv, contains('shift_id,completed_at,platforms,gross_earnings'));
    expect(csv, contains('shift-1,2026-08-20T18:30:00.000,Uber,100.00'));
    expect(csv, contains(',15.00,75.00,manual'));
    expect(csv.split('\r\n').where((row) => row.isNotEmpty), hasLength(2));
  });

  test('CSV export escapes values that contain commas or quotes', () {
    expect(ShiftExport.csv(const []), endsWith('\r\n'));
    // Exercise the private encoder through a platform combination whose
    // display value remains a single cell.
    final shift = Shift(
      id: 'multi,shift',
      earnings: const {WorkPlatform.uber: 60, WorkPlatform.lyft: 40},
      hours: 4,
      miles: 50,
      directExpenses: 10,
      vehicleCostPerMile: .30,
      completedAt: DateTime(2026, 8, 20),
      source: ShiftSource.manual,
    );

    expect(ShiftExport.csv([shift]), contains('"multi,shift"'));
  });
}
