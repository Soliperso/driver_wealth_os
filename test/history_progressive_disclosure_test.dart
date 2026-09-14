import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('one shift keeps every History insight discoverable', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [_shift(id: 'current')],
      ),
    );

    await tester.pumpWidget(KeeprateApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Profit by day'), 200);
    expect(find.text('Profit by day'), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-style-bars')), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-style-line')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chart-style-line')));
    await tester.pumpAndSettle();
    expect(find.text('Tap a point for its full numbers.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Platform comparison'), 200);
    expect(
      find.byKey(const ValueKey('platform-comparison-learning')),
      findsOneWidget,
    );
    // Earnings DNA is not on History. It is one reading of one data set, and
    // it lives on Coach's Best times screen — History used to print a second
    // copy of the same grid and the same progress line.
    expect(find.text('Earnings DNA'), findsNothing);
    await tester.scrollUntilVisible(find.text('Sessions this week'), 200);
    expect(find.text('Sessions this week'), findsOneWidget);
    expect(find.textContaining('All time'), findsNothing);
  });

  testWidgets('the shift list follows the period until View all is chosen', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [
          _shift(id: 'current'),
          _shift(
            id: 'older',
            completedAt: DateTime.now().subtract(const Duration(days: 40)),
          ),
        ],
      ),
    );

    await tester.pumpWidget(KeeprateApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('history-shift-current')),
      200,
    );
    expect(find.byKey(const ValueKey('history-shift-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-shift-older')), findsNothing);
    await tester.scrollUntilVisible(find.text('View all sessions'), 200);
    // scrollUntilVisible stops as soon as the finder matches, which can leave
    // the link under the floating bottom bar with the tap missing it.
    await tester.ensureVisible(find.text('View all sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View all sessions'));
    await tester.pumpAndSettle();

    expect(find.text('All sessions'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-shift-older')), findsOneWidget);
  });

  testWidgets('an empty period offers the nearest session instead of cards', (
    tester,
  ) async {
    // Far enough back that neither this week nor last week contains it.
    final past = DateTime.now().subtract(const Duration(days: 21));
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [_shift(id: 'past', completedAt: past)],
      ),
    );

    await tester.pumpWidget(KeeprateApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('nearest-session-card')), findsOneWidget);
    expect(find.textContaining('Your most recent session was'), findsOneWidget);
    // The analytics stack has nothing to read, so it is not drawn at all.
    expect(find.text('Profit by day'), findsNothing);
    expect(find.text('Platform comparison'), findsNothing);
    expect(find.text('View all sessions'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('go-to-nearest-session')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('nearest-session-card')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('history-shift-past')),
      200,
    );
    expect(find.byKey(const ValueKey('history-shift-past')), findsOneWidget);
  });

  testWidgets('a gap between sessions points at the one before it', (
    tester,
  ) async {
    // A week with sessions on both sides of it: "most recent" would be wrong
    // there, and the longest wording is also the one most likely to overflow.
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [
          _shift(id: 'recent'),
          _shift(
            id: 'older',
            completedAt: DateTime.now().subtract(const Duration(days: 21)),
          ),
        ],
      ),
    );

    await tester.pumpWidget(KeeprateApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    // Back two weeks, into the gap between the two sessions.
    await tester.tap(find.byKey(const ValueKey('period-previous')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('period-previous')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The nearest session before this was'),
      findsOneWidget,
    );
    expect(find.textContaining('Your most recent session'), findsNothing);
  });

  testWidgets('an unreviewed import gets one compact cost warning', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [
          _shift(
            id: 'imported',
            source: ShiftSource.imported,
            costsReviewed: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(KeeprateApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cost-review-notice')), findsOneWidget);
    expect(find.text('Review costs for 1 imported session'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-imported-costs')));
    await tester.pumpAndSettle();
    expect(find.text('Session details'), findsOneWidget);
  });

  testWidgets('platform comparison waits for two reviewed shifts each', (
    tester,
  ) async {
    final store = MemoryAppStore(
      AppSnapshot(
        driverName: 'Ahmed',
        shifts: [
          _shift(id: 'uber-1'),
          _shift(id: 'uber-2'),
          _shift(id: 'lyft-1', platform: WorkPlatform.lyft),
          _shift(id: 'lyft-2', platform: WorkPlatform.lyft),
        ],
      ),
    );

    await tester.pumpWidget(KeeprateApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Platform comparison'), 200);
    expect(find.text('Platform comparison'), findsOneWidget);
    expect(
      find.text('Based on reviewed costs and at least 2 sessions each.'),
      findsOneWidget,
    );
    // The pattern reading itself is Coach's, and is covered there.
    expect(find.text('Earnings DNA'), findsNothing);
  });

  test('old imported records migrate into cost review safely', () {
    final json = _shift(id: 'legacy', source: ShiftSource.imported).toJson()
      ..remove('costsReviewed');

    final restored = Shift.fromJson(json);

    expect(restored.costsReviewed, isFalse);
    expect(restored.copyWith(costsReviewed: true).costsReviewed, isTrue);
  });
}

Shift _shift({
  required String id,
  DateTime? completedAt,
  WorkPlatform platform = WorkPlatform.uber,
  ShiftSource source = ShiftSource.manual,
  bool costsReviewed = true,
}) => Shift.single(
  id: id,
  platform: platform,
  gross: 120,
  hours: 2,
  miles: 20,
  directExpenses: 10,
  vehicleCostPerMile: .20,
  completedAt:
      completedAt ??
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
  source: source,
  costsReviewed: costsReviewed,
);
