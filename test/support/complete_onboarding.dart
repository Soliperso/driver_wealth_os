import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Walks first-run setup end to end and lands on Today.
///
/// Shared because onboarding is now five steps rather than one field, and every
/// test that needs a set-up app was otherwise repeating the same taps — which
/// is what made the previous change to this flow touch four unrelated tests.
///
/// Only the name is required; every other step ships with a working default, so
/// the helper accepts them and moves on unless a test asks otherwise.
Future<void> completeOnboarding(
  WidgetTester tester, {
  String name = 'Ahmed',
  String? dailyGoal,
  String? vehicleRate,
}) async {
  await tester.pumpAndSettle();

  // Step 0: the value-prop screen has nothing to fill in.
  await _tapContinue(tester);

  await tester.enterText(find.byKey(const ValueKey('onboarding-name')), name);
  await _tapContinue(tester);

  if (dailyGoal != null) {
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-goal')),
      dailyGoal,
    );
  }
  await _tapContinue(tester);

  if (vehicleRate != null) {
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-vehicle-rate')),
      vehicleRate,
    );
  }
  await _tapContinue(tester);

  // Step 4: the tracking primer, whose button finishes rather than continues.
  await tester.tap(find.byKey(const ValueKey('onboarding-finish')));
  await tester.pumpAndSettle();
}

Future<void> _tapContinue(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('onboarding-continue'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
