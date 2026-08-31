// Renders the screens a driver sees before they are inside the app, so they
// can actually be looked at.
//
//   flutter test test/visual --update-goldens
//
// These are the layouts nothing else checks: onboarding and every step of the
// auth flow share one hero template, and the failure mode is a card that reads
// flat against the background or a step whose links overflow — neither of
// which a behavioural test would notice.
@Tags(['visual'])
library;

import 'dart:async';
import 'dart:io';

import 'package:driver_wealth_os/core/theme/app_theme.dart';
import 'package:driver_wealth_os/features/auth/application/auth_gateway.dart';
import 'package:driver_wealth_os/features/auth/domain/auth_user.dart';
import 'package:driver_wealth_os/features/auth/presentation/auth_flow_screen.dart';
import 'package:driver_wealth_os/features/onboarding/presentation/onboarding_screen.dart';
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

/// Names the font on the styles that do not carry one.
///
/// `filledButtonTheme` sets a `const TextStyle` with no family, so on a real
/// device the label takes the platform's default face. In the test renderer
/// that default draws every glyph as a filled box, which turns every primary
/// button in these captures into a white bar. Only the family is supplied —
/// size, weight and tracking stay exactly as the app ships them.
ThemeData _readable(ThemeData theme) => theme.copyWith(
  filledButtonTheme: FilledButtonThemeData(
    style: theme.filledButtonTheme.style?.copyWith(
      textStyle: WidgetStateProperty.all(
        theme.filledButtonTheme.style?.textStyle
                ?.resolve({})
                ?.copyWith(fontFamily: 'Roboto') ??
            const TextStyle(fontFamily: 'Roboto'),
      ),
    ),
  ),
);

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
    List<String> tapKeys = const [],
    Map<String, String> fill = const {},
  }) async {
    const dpr = 2.0;
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _readable(AppTheme.light),
        darkTheme: _readable(AppTheme.dark),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: child,
      ),
    );

    // The brand mark is a real image now. Asset decoding is asynchronous, so
    // without this it paints as an empty box and the one thing these captures
    // exist to confirm would be invisible.
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/icon/app_mark.png'),
        tester.element(find.byType(MaterialApp)),
      );
    });
    await tester.pumpAndSettle();

    for (final key in tapKeys) {
      // A step is often only reachable once the one before it validates, so
      // fields are filled between taps rather than all at the start.
      for (final entry in fill.entries) {
        final field = find.byKey(ValueKey(entry.key));
        if (field.evaluate().isEmpty) continue;
        await tester.enterText(field, entry.value);
        await tester.pumpAndSettle();
      }
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/$name.png'),
    );
  }

  Widget onboarding() => OnboardingScreen(onComplete: (_) {});
  Widget auth() => AuthFlowScreen(gateway: _StillGateway());

  testWidgets('onboarding light', (tester) async {
    await capture(tester, 'first_run_onboarding_light', onboarding());
  });

  testWidgets('onboarding dark', (tester) async {
    await capture(
      tester,
      'first_run_onboarding_dark',
      onboarding(),
      brightness: Brightness.dark,
    );
  });

  testWidgets('login light', (tester) async {
    await capture(tester, 'first_run_login_light', auth());
  });

  testWidgets('login dark', (tester) async {
    await capture(
      tester,
      'first_run_login_dark',
      auth(),
      brightness: Brightness.dark,
    );
  });

  testWidgets('sign up', (tester) async {
    await capture(
      tester,
      'first_run_sign_up',
      auth(),
      tapKeys: ['go-create-account'],
    );
  });

  testWidgets('forgot password', (tester) async {
    await capture(
      tester,
      'first_run_forgot_password',
      auth(),
      tapKeys: ['go-forgot-password'],
    );
  });

  testWidgets('code sign-in', (tester) async {
    await capture(
      tester,
      'first_run_code_sign_in',
      auth(),
      tapKeys: ['go-code-sign-in'],
    );
  });

  testWidgets('reset password', (tester) async {
    await capture(
      tester,
      'first_run_reset_password',
      // Only the send has to complete for the reset step to be reachable.
      AuthFlowScreen(gateway: _StillGateway(sendsReset: true)),
      tapKeys: ['go-forgot-password', 'forgot-submit'],
      fill: {'forgot-email-field': 'driver@example.com'},
    );
  });
}

/// A gateway that never answers. These captures are of layout, not behaviour,
/// so nothing here should ever complete and change the screen mid-capture.
class _StillGateway implements AuthGateway {
  _StillGateway({this.sendsReset = false});

  /// Lets the reset request succeed, so the step that follows it can be
  /// captured. Everything else still hangs.
  final bool sendsReset;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get changes => const Stream.empty();

  @override
  Future<AuthUser> signIn({required String email, required String password}) =>
      Completer<AuthUser>().future;

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String name,
  }) => Completer<AuthUser>().future;

  @override
  Future<void> sendCode(String email) => Completer<void>().future;

  @override
  Future<void> deleteAccount() => Completer<void>().future;

  @override
  Future<AuthUser> verifyCode({required String email, required String code}) =>
      Completer<AuthUser>().future;

  @override
  Future<void> sendPasswordReset(String email) async {
    if (!sendsReset) return Completer<void>().future;
  }

  @override
  Future<AuthUser> verifyPasswordReset({
    required String email,
    required String code,
  }) => Completer<AuthUser>().future;

  @override
  Future<void> updatePassword(String password) => Completer<void>().future;

  @override
  Future<void> signOut() async {}
}
