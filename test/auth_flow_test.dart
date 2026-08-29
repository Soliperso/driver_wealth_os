import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/accounts/domain/work_platform.dart';
import 'package:driver_wealth_os/features/auth/application/auth_gateway.dart';
import 'package:driver_wealth_os/features/auth/domain/auth_user.dart';
import 'package:driver_wealth_os/features/shifts/domain/shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_gateway.dart';
import 'support/fake_location_tracker.dart';

/// The point of these tests is the thing the app previously could not do:
/// survive a reinstall. An anonymous session could not be recovered by anyone,
/// so a driver's whole history depended on one device's storage.
///
/// A password is the front door; the emailed code is the second one, kept so
/// that forgetting a password is not the same as losing the account.
void main() {
  Shift shift(String id) => Shift.single(
    id: id,
    platform: WorkPlatform.uber,
    gross: 200,
    hours: 5,
    miles: 100,
    directExpenses: 20,
    vehicleCostPerMile: .20,
    completedAt: DateTime(2026, 8, 11, 18),
  );

  Future<void> pumpApp(
    WidgetTester tester, {
    required AppStore store,
    required AuthGateway gateway,
    required FakeLocationTracker tracker,
  }) async {
    await tester.pumpWidget(
      DriverWealthApp(
        store: store,
        authGateway: gateway,
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps something that may be below the fold.
  Future<void> press(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// The code flow is now reached from the login screen rather than being the
  /// screen itself.
  Future<void> goToCodeSignIn(WidgetTester tester) =>
      press(tester, 'go-code-sign-in');

  testWidgets('a signed-out driver is asked to sign in before anything else', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    // Sign-in precedes even onboarding: the name belongs to an account.
    expect(find.byKey(const ValueKey('login-email-field')), findsOneWidget);
    expect(find.text('Hi, Ahmed!'), findsNothing);
  });

  testWidgets('an email and password sign the driver in', (tester) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    gateway.passwords['driver@example.com'] = 'CorrectHorse9';
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    await tester.enterText(
      find.byKey(const ValueKey('login-email-field')),
      'driver@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password-field')),
      'CorrectHorse9',
    );
    await press(tester, 'login-submit');

    expect(find.text('Hi, Ahmed!'), findsOneWidget);
  });

  testWidgets('a wrong password is reported and signs nobody in', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    gateway.passwords['driver@example.com'] = 'CorrectHorse9';
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    await tester.enterText(
      find.byKey(const ValueKey('login-email-field')),
      'driver@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password-field')),
      'WrongHorse9',
    );
    await press(tester, 'login-submit');

    expect(find.byKey(const ValueKey('sign-in-error')), findsOneWidget);
    expect(find.textContaining('do not match an account'), findsOneWidget);
    expect(find.text('Hi, Ahmed!'), findsNothing);
  });

  testWidgets('signing up names the driver without asking a second time', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    addTearDown(gateway.dispose);

    // Nothing stored: without the signup name this device would land on
    // onboarding and ask for it again.
    await pumpApp(
      tester,
      store: MemoryAppStore(),
      gateway: gateway,
      tracker: tracker,
    );

    await press(tester, 'go-create-account');
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-name-field')),
      'Ahmed',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-email-field')),
      'new@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-password-field')),
      'CorrectHorse9',
    );
    await press(tester, 'sign-up-submit');

    expect(gateway.signedUpName, 'Ahmed');
    expect(find.text('Drive smarter.\nKeep more.'), findsNothing);
    expect(find.text('Hi, Ahmed!'), findsOneWidget);
  });

  testWidgets('a password too weak for the backend never leaves the device', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(),
      gateway: gateway,
      tracker: tracker,
    );

    await press(tester, 'go-create-account');
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-name-field')),
      'Ahmed',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-email-field')),
      'new@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-password-field')),
      'short',
    );
    await press(tester, 'sign-up-submit');

    // Checked here rather than round-tripped, so the rejection is written for
    // a driver instead of quoted from the provider.
    expect(find.textContaining('at least 10 characters'), findsOneWidget);
    expect(gateway.signedUpName, isNull);
    expect(gateway.passwords, isEmpty);
  });

  testWidgets('a forgotten password is reset with an emailed code', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    gateway.passwords['driver@example.com'] = 'ForgottenOne9';
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    await press(tester, 'go-forgot-password');
    await tester.enterText(
      find.byKey(const ValueKey('forgot-email-field')),
      'driver@example.com',
    );
    await press(tester, 'forgot-submit');

    expect(gateway.resetsSentTo, ['driver@example.com']);

    await tester.enterText(
      find.byKey(const ValueKey('reset-code-field')),
      '654321',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reset-password-field')),
      'BrandNewOne9',
    );
    await press(tester, 'reset-submit');

    // Signed in on the new password, and the old one no longer opens the
    // account.
    expect(find.text('Hi, Ahmed!'), findsOneWidget);
    expect(gateway.passwords['driver@example.com'], 'BrandNewOne9');
  });

  testWidgets('a wrong reset code leaves the password alone', (tester) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    gateway.passwords['driver@example.com'] = 'ForgottenOne9';
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    await press(tester, 'go-forgot-password');
    await tester.enterText(
      find.byKey(const ValueKey('forgot-email-field')),
      'driver@example.com',
    );
    await press(tester, 'forgot-submit');

    await tester.enterText(
      find.byKey(const ValueKey('reset-code-field')),
      '000000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reset-password-field')),
      'BrandNewOne9',
    );
    await press(tester, 'reset-submit');

    expect(find.byKey(const ValueKey('sign-in-error')), findsOneWidget);
    expect(gateway.passwords['driver@example.com'], 'ForgottenOne9');
    expect(find.text('Hi, Ahmed!'), findsNothing);
  });

  testWidgets('email then code signs the driver in', (tester) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    await goToCodeSignIn(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-email-field')),
      'driver@example.com',
    );
    await press(tester, 'send-code-button');

    expect(gateway.sentTo, ['driver@example.com']);
    expect(find.byKey(const ValueKey('sign-in-code-field')), findsOneWidget);
    expect(find.textContaining('driver@example.com'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('sign-in-code-field')),
      '123456',
    );
    await press(tester, 'verify-code-button');

    // Straight through to the dashboard — the saved name is already there.
    expect(find.text('Hi, Ahmed!'), findsOneWidget);
  });

  testWidgets('a wrong code is reported and does not sign anyone in', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    await goToCodeSignIn(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-email-field')),
      'driver@example.com',
    );
    await press(tester, 'send-code-button');

    await tester.enterText(
      find.byKey(const ValueKey('sign-in-code-field')),
      '000000',
    );
    await press(tester, 'verify-code-button');

    expect(find.byKey(const ValueKey('sign-in-error')), findsOneWidget);
    expect(find.textContaining('expired or is incorrect'), findsOneWidget);
    expect(find.text('Hi, Ahmed!'), findsNothing);
  });

  testWidgets('a failure to send is shown rather than swallowed', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway()
      ..sendFailure = const AuthException(
        'Too many attempts. Wait a minute before trying again.',
      );
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    await goToCodeSignIn(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-email-field')),
      'driver@example.com',
    );
    await press(tester, 'send-code-button');

    expect(find.textContaining('Too many attempts'), findsOneWidget);
    // Still on the email step — advancing would strand the driver waiting for
    // a code that was never sent.
    expect(find.byKey(const ValueKey('sign-in-email-field')), findsOneWidget);
  });

  testWidgets('a malformed email never reaches the backend', (tester) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway();
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
      gateway: gateway,
      tracker: tracker,
    );

    await goToCodeSignIn(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-email-field')),
      'not-an-email',
    );
    await press(tester, 'send-code-button');

    expect(gateway.sentTo, isEmpty);
    expect(find.textContaining('does not look right'), findsOneWidget);
  });

  testWidgets('a restored session goes straight to the dashboard', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway(
      user: const AuthUser(id: 'user-1', email: 'driver@example.com'),
    );
    addTearDown(gateway.dispose);

    await pumpApp(
      tester,
      store: MemoryAppStore(
        AppSnapshot(driverName: 'Ahmed', shifts: [shift('a')]),
      ),
      gateway: gateway,
      tracker: tracker,
    );

    // No network is involved in restoring a session, so this is also the
    // offline-launch path.
    expect(find.byKey(const ValueKey('login-email-field')), findsNothing);
    expect(find.text('Hi, Ahmed!'), findsOneWidget);
  });

  testWidgets('signing out clears this device and returns to sign-in', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);
    final gateway = FakeAuthGateway(
      user: const AuthUser(id: 'user-1', email: 'driver@example.com'),
    );
    addTearDown(gateway.dispose);
    final store = MemoryAppStore(
      AppSnapshot(driverName: 'Ahmed', shifts: [shift('a')]),
    );

    await pumpApp(tester, store: store, gateway: gateway, tracker: tracker);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // Settings is a lazy ListView, so the account card has to be scrolled to
    // before it exists in the tree at all.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-sign-out')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('driver@example.com'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-sign-out')));
    await tester.pumpAndSettle();

    // Confirmed, because it removes data from the device.
    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-sign-out')));
    await tester.pumpAndSettle();

    expect(gateway.signOutCount, 1);
    expect(find.byKey(const ValueKey('login-email-field')), findsOneWidget);
    // The next driver to use this phone must not inherit the last one's money.
    expect(store.snapshot.shifts, isEmpty);
    expect(store.snapshot.driverName, isNull);
  });

  testWidgets('a build with no backend never asks anyone to sign in', (
    tester,
  ) async {
    final tracker = FakeLocationTracker();
    addTearDown(tracker.dispose);

    // No gateway injected and no backend configured in the test environment,
    // so the app stays local-only exactly as it did before accounts existed.
    await tester.pumpWidget(
      DriverWealthApp(
        store: MemoryAppStore(const AppSnapshot(driverName: 'Ahmed')),
        locationTracker: tracker,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-email-field')), findsNothing);
    expect(find.text('Hi, Ahmed!'), findsOneWidget);
  });
}
