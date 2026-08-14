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

/// Email sign-in, reduced to the two steps the driver experiences.
///
/// Passwordless on purpose. A password would add a reset flow, a strength
/// policy and a place for the driver to get locked out of their own earnings
/// history — all to protect data they can already reach from their inbox.
abstract interface class AuthGateway {
  AuthUser? get currentUser;

  /// Emits on every sign-in and sign-out, including the silent restore that
  /// happens at launch when a stored session is still valid.
  Stream<AuthUser?> get changes;

  /// Sends a one-time code to [email].
  Future<void> sendCode(String email);

  /// Exchanges the emailed code for a session.
  Future<AuthUser> verifyCode({required String email, required String code});

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
  Future<void> sendCode(String email) async {
    try {
      await _client.auth.signInWithOtp(
        email: email,
        // Without this a brand-new address would be rejected rather than
        // enrolled, which for a passwordless flow is just "sign up".
        shouldCreateUser: true,
      );
    } on AuthApiException catch (error) {
      throw AuthException(_readable(error));
    } catch (_) {
      throw const AuthException(
        'We could not send your code. Check your connection and try again.',
      );
    }
  }

  @override
  Future<AuthUser> verifyCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
      final user = _toUser(response.session?.user);
      if (user == null) {
        throw const AuthException('That code did not work. Try again.');
      }
      return user;
    } on AuthApiException catch (error) {
      throw AuthException(_readable(error));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'We could not verify your code. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// Turns the provider's error into something a driver can act on.
  ///
  /// Only the cases that are actually distinguishable and actionable are
  /// translated; everything else stays generic rather than leaking a raw API
  /// string into the interface.
  static String _readable(AuthApiException error) {
    final code = error.code ?? '';
    if (code.contains('otp_expired') || code.contains('invalid_credentials')) {
      return 'That code has expired or is incorrect. Request a new one.';
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
