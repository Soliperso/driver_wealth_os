import 'package:driver_wealth_os/core/sync/sync_service.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter_test/flutter_test.dart';

/// A driver with Uber and Lyft both live in the same car for the same six
/// hours. The figures are shared; only the money divides.
Shift multiAppShift({
  Map<WorkPlatform, double>? earnings,
  double hours = 6,
  double miles = 120,
}) => Shift(
  id: 'tracked-1',
  earnings: earnings ?? {WorkPlatform.uber: 142.50, WorkPlatform.lyft: 38},
  hours: hours,
  miles: miles,
  directExpenses: 20,
  vehicleCostPerMile: .30,
  completedAt: DateTime(2026, 8, 14, 18),
);

void main() {
  group('a shift running several apps at once', () {
    test('counts its hours and miles once, not once per platform', () {
      final shift = multiAppShift();

      // The whole reason earnings are lines on one shift rather than separate
      // shifts: two records would bill 12 hours and 240 miles for one evening.
      expect(shift.hours, 6);
      expect(shift.miles, 120);
      expect(shift.vehicleCost, 36);
      expect(shift.gross, 180.50);
      expect(shift.netProfit, 124.50);
      expect(shift.netPerHour, closeTo(20.75, .0001));
    });

    test('attributes gross per platform and nothing else', () {
      final shift = multiAppShift();

      expect(shift.earnedOn(WorkPlatform.uber), 142.50);
      expect(shift.earnedOn(WorkPlatform.lyft), 38);
      expect(shift.earnedOn(WorkPlatform.doorDash), 0);
      expect(shift.shareOf(WorkPlatform.uber), closeTo(.7895, .0001));
      expect(shift.shareOf(WorkPlatform.lyft), closeTo(.2105, .0001));
    });

    test('names itself by the app that paid most', () {
      expect(multiAppShift().platform, WorkPlatform.uber);
      expect(multiAppShift().platformLabel, 'Uber + Lyft');
      expect(multiAppShift().isMultiApp, isTrue);

      final threeApps = multiAppShift(
        earnings: {
          WorkPlatform.lyft: 20,
          WorkPlatform.uber: 90,
          WorkPlatform.doorDash: 45,
        },
      );
      expect(threeApps.platform, WorkPlatform.uber);
      expect(threeApps.platformLabel, 'Uber + 2 more');
      expect(threeApps.platformsByEarnings, [
        WorkPlatform.uber,
        WorkPlatform.doorDash,
        WorkPlatform.lyft,
      ]);
    });

    test('keeps entry order when nothing has been paid yet', () {
      // A shift that has just stopped tracking: every line is still zero, and
      // the display must not reshuffle underneath the driver.
      final draft = multiAppShift(
        earnings: {WorkPlatform.lyft: 0, WorkPlatform.uber: 0},
      );

      expect(draft.platform, WorkPlatform.lyft);
      expect(draft.platformLabel, 'Lyft + Uber');
      expect(draft.shareOf(WorkPlatform.lyft), 0);
    });

    test('a single-platform shift behaves exactly as it did before', () {
      final shift = Shift.single(
        id: 'manual-1',
        platform: WorkPlatform.doorDash,
        gross: 120,
        hours: 4,
        miles: 60,
        directExpenses: 10,
        vehicleCostPerMile: .30,
        completedAt: DateTime(2026),
      );

      expect(shift.platform, WorkPlatform.doorDash);
      expect(shift.platformLabel, 'DoorDash');
      expect(shift.isMultiApp, isFalse);
      expect(shift.gross, 120);
      expect(shift.netProfit, 92);
      expect(shift.shareOf(WorkPlatform.doorDash), 1);
    });
  });

  group('storage', () {
    test('round trips every earnings line', () {
      final restored = Shift.fromJson(multiAppShift().toJson());

      expect(restored.earnings, {
        WorkPlatform.uber: 142.50,
        WorkPlatform.lyft: 38,
      });
      expect(restored.gross, 180.50);
      expect(restored.hours, 6);
    });

    test('writes the legacy platform and gross for an older build', () {
      final json = multiAppShift().toJson();

      // What a build without multi-app support reads: the dominant app and the
      // whole day's takings. Lossy, but it beats an empty history.
      expect(json['platform'], WorkPlatform.uber.id);
      expect(json['gross'], 180.50);
    });

    test('reads a record written before earnings lines existed', () {
      final legacy = {
        'id': 'manual-old',
        'platform': 'lyft',
        'gross': 210.0,
        'hours': 7.0,
        'miles': 90.0,
        'directExpenses': 15.0,
        'vehicleCostPerMile': .30,
        'completedAt': DateTime(2026, 3, 2).toIso8601String(),
        'source': 'manual',
        'costsReviewed': true,
      };

      final restored = Shift.fromJson(legacy);

      expect(restored.earnings, {WorkPlatform.lyft: 210.0});
      expect(restored.gross, 210);
      expect(restored.isMultiApp, isFalse);
    });

    test('sums two unrecognised providers instead of dropping one', () {
      // Both map to `other`. Assigning rather than summing would silently halve
      // this driver's gross for the shift.
      final shift = Shift.fromJson({
        'id': 'imported-1',
        'platform': 'other',
        'gross': 80.0,
        'earnings': [
          {'platform': 'some_new_app', 'gross': 50.0},
          {'platform': 'another_new_app', 'gross': 30.0},
        ],
        'hours': 4.0,
        'miles': 40.0,
        'directExpenses': 0.0,
        'vehicleCostPerMile': .30,
        'completedAt': DateTime(2026, 3, 2).toIso8601String(),
        'source': 'imported',
      });

      expect(shift.earnings, {WorkPlatform.other: 80.0});
      expect(shift.gross, 80);
    });
  });

  group('sync rows', () {
    Map<String, Object?> row(Map<String, Object?> overrides) => {
      'id': 'tracked-1',
      'platform': 'uber',
      'gross': '180.50',
      'hours': '6',
      'miles': '120',
      'direct_expenses': '20',
      'vehicle_cost_per_mile': '0.30',
      'completed_at': DateTime.utc(2026, 8, 14, 18).toIso8601String(),
      'source': 'tracked',
      'costs_reviewed': true,
      ...overrides,
    };

    test('reads earnings lines off a pulled row', () {
      final shift = SupabaseSyncService.rowToShift(
        row({
          'earnings': [
            {'platform': 'uber', 'gross': 142.50},
            {'platform': 'lyft', 'gross': 38},
          ],
        }),
      );

      expect(shift, isNotNull);
      expect(shift!.earnings, {
        WorkPlatform.uber: 142.50,
        WorkPlatform.lyft: 38,
      });
      expect(shift.gross, 180.50);
    });

    test('falls back to the legacy columns before the migration runs', () {
      final shift = SupabaseSyncService.rowToShift(row({}));

      expect(shift!.earnings, {WorkPlatform.uber: 180.50});
    });

    test('one malformed earnings line does not abort the sync', () {
      // rowToShift returns null rather than throwing, and a bad amount inside
      // the lines must not become an exception that strands every other
      // pending change behind it.
      final shift = SupabaseSyncService.rowToShift(
        row({
          'earnings': [
            {'platform': 'uber', 'gross': 142.50},
            {'platform': 'lyft', 'gross': 'not a number'},
          ],
        }),
      );

      expect(shift, isNotNull);
      expect(shift!.earnedOn(WorkPlatform.uber), 142.50);
      expect(shift.earnedOn(WorkPlatform.lyft), 0);
    });
  });
}
