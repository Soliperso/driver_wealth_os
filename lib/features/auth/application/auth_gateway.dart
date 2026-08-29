import 'dart:async';

// The provider exports its own `AuthUser` and `AuthException`. Both are hidden
// so the names in this file are unambiguously ours — the whole point of the
// gateway is that nothing above it deals in provider types.
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthException, AuthUser;

import '../domain/auth_user.dart';

/// Raised when a sign-in step fails for a reason worth showing the driver.
///
/// The message is the one the UI renders, so it is written for a driver rather
/// than derived from a provider error string.
final class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything a driver can do to get into their account.
///
/// Two ways in, deliberately. A password is what most people expect and is the
/// only practical option once staff accounts exist, but it also creates the
/// lockout the passwordless flow was built to avoid. So the emailed code
/// stays: it is a second door for anyone who has forgotten their password, and
/// the accounts created before passwords existed still open with it.
abstract interface class AuthGateway {
  AuthUser? get currentUser;

  /// Emits on every sign-in and sign-out, including the silent restore that
  /// happens at launch when a stored session is still valid.
  Stream<AuthUser?> get changes;

  /// Signs in an existing account with its password.
  Future<AuthUser> signIn({required String email, required String password});

  /// Creates an account. [name] is the driver's first name, stored on the
  /// account so a reinstall does not have to ask for it again.
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String name,
  });

  /// Sends a one-time code to [email].
  Future<void> sendCode(String email);

  /// Exchanges the emailed code for a session.
  Future<AuthUser> verifyCode({required String email, required String code});

  /// Emails a recovery code for a forgotten password.
  ///
  /// A code rather than a link: a link has to reopen the app, which means
  /// universal links on iOS and app links on Android, and a driver stranded in
  /// a browser whenever that configuration is wrong.
  Future<void> sendPasswordReset(String email);

  /// Exchanges a recovery code for the short-lived session that
  /// [updatePassword] needs.
  Future<AuthUser> verifyPasswordReset({
    required String email,
    required String code,
  });

  /// Sets a new password on the currently signed-in account.
  Future<void> updatePassword(String password);

  Future<void> signOut();
}

final class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  AuthUser? get currentUser => _toUser(_client.auth.currentSession?.user);

  @override
  Stream<AuthUser?> get changes => _client.auth.onAuthStateChange.map(
    (event) => _toUser(event.session?.user),
  );

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) => _guard(() async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return _require(response.session?.user, 'We could not sign you in.');
  }, 'We could not sign you in. Check your connection and try again.', rejected: 'That email and password do not match an account.');

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String name,
  }) => _guard(() async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      // Carried on the account so a new phone can greet the driver by name
      // before the first sync has finished.
      data: {'driver_name': name},
    );
    // Email confirmation is off for this project, so a session comes back
    // immediately. If it is ever turned on, this is where signup would have to
    // grow a confirmation step rather than silently failing.
    return _require(
      response.session?.user,
      'Your account was created, but needs confirming by email before you can '
      'sign in.',
    );
  }, 'We could not create your account. Check your connection and try again.');

  @override
  Future<void> sendCode(String email) => _guard(() async {
    await _client.auth.signInWithOtp(
      email: email,
      // Without this a brand-new address would be rejected rather than
      // enrolled, which for a passwordless flow is just "sign up".
      shouldCreateUser: true,
    );
  }, 'We could not send your code. Check your connection and try again.');

  @override
  Future<AuthUser> verifyCode({
    required String email,
    required String code,
  }) => _guard(() async {
    final response = await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
    return _require(
      response.session?.user,
      'That code did not work. Try again.',
    );
  }, 'We could not verify your code. Check your connection and try again.', rejected: 'That code has expired or is incorrect. Request a new one.');

  @override
  Future<void> sendPasswordReset(String email) => _guard(() async {
    await _client.auth.resetPasswordForEmail(email);
  }, 'We could not send your reset code. Check your connection and try again.');

  @override
  Future<AuthUser> verifyPasswordReset({
    required String email,
    required String code,
  }) => _guard(() async {
    final response = await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.recovery,
    );
    return _require(
      response.session?.user,
      'That reset code did not work. Request a new one.',
    );
  }, 'We could not check your reset code. Check your connection and try again.', rejected: 'That reset code has expired or is incorrect. Request a new one.');

  @override
  Future<void> updatePassword(String password) => _guard(() async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }, 'We could not save your new password. Check your connection and try again.');

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// Runs [action], turning provider failures into an [AuthException] the UI
  /// can render.
  ///
  /// Every call does the same three things with errors, and doing them by hand
  /// in each method is how one of them ends up leaking a raw API string.
  static Future<T> _guard<T>(
    Future<T> Function() action,
    String fallback, {
    String rejected = 'That did not match. Check it and try again.',
  }) async {
    try {
      return await action();
    } on AuthApiException catch (error) {
      throw AuthException(_readable(error, rejected: rejected));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException(fallback);
    }
  }

  static AuthUser _require(User? user, String message) {
    final result = _toUser(user);
    if (result == null) throw AuthException(message);
    return result;
  }

  /// Turns the provider's error into something a driver can act on.
  ///
  /// Only the cases that are actually distinguishable and actionable are
  /// translated; everything else stays generic rather than leaking a raw API
  /// string into the interface.
  ///
  /// [rejected] is what "we did not accept that" means for the step being
  /// attempted. The provider reports a wrong password and a wrong one-time
  /// code with the same codes, so only the caller knows which of the two the
  /// driver just typed.
  static String _readable(
    AuthApiException error, {
    required String rejected,
  }) {
    final code = error.code ?? '';
    if (code.contains('invalid_credentials') || code.contains('otp_expired')) {
      return rejected;
    }
    if (code.contains('user_already_exists') ||
        code.contains('email_exists')) {
      return 'That email already has an account. Sign in instead.';
    }
    if (code.contains('weak_password')) {
      return 'That password is too easy to guess. Try a longer one.';
    }
    if (code.contains('same_password')) {
      return 'That is already your password. Choose a different one.';
    }
    if (code.contains('over_email_send_rate_limit') ||
        code.contains('over_request_rate_limit')) {
      return 'Too many attempts. Wait a minute before trying again.';
    }
    if (code.contains('validation_failed')) {
      return 'That email address does not look right.';
    }
    return 'Sign-in failed. Please try again.';
  }

  static AuthUser? _toUser(User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);
}
