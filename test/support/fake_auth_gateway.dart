import 'dart:async';

import 'package:driver_wealth_os/features/auth/application/auth_gateway.dart';
import 'package:driver_wealth_os/features/auth/domain/auth_user.dart';

/// An in-memory account, so sign-in can be tested without a network or an
/// inbox.
class FakeAuthGateway implements AuthGateway {
  /// A non-null [user] stands in for a stored session restored at launch.
  FakeAuthGateway({this.user});

  AuthUser? user;
  final _controller = StreamController<AuthUser?>.broadcast();

  /// The code the fake will accept. Anything else is rejected the way a wrong
  /// or expired code would be.
  String validCode = '123456';

  /// The recovery code [verifyPasswordReset] accepts.
  String validResetCode = '654321';

  /// Accounts that already exist, as email to password. Seed it to test
  /// signing in; leave it empty to test signing up.
  final passwords = <String, String>{};

  /// When set, [sendCode] throws it — the delivery failures a driver actually
  /// hits: rate limits, bad addresses, no connection.
  AuthException? sendFailure;

  /// When set, [signUp] throws it — the duplicate address and weak-password
  /// rejections that only the backend can decide.
  AuthException? signUpFailure;

  var sentTo = <String>[];
  var resetsSentTo = <String>[];
  var signOutCount = 0;

  /// The name [signUp] was given, so a test can prove it reaches the app
  /// rather than being asked for a second time.
  String? signedUpName;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> get changes => _controller.stream;

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    if (passwords[email] != password) {
      throw const AuthException(
        'That email and password do not match an account.',
      );
    }
    return _signIn(email);
  }

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final failure = signUpFailure;
    if (failure != null) throw failure;
    if (passwords.containsKey(email)) {
      throw const AuthException(
        'That email already has an account. Sign in instead.',
      );
    }
    passwords[email] = password;
    signedUpName = name;
    return _signIn(email);
  }

  @override
  Future<void> sendCode(String email) async {
    final failure = sendFailure;
    if (failure != null) throw failure;
    sentTo.add(email);
  }

  @override
  Future<AuthUser> verifyCode({
    required String email,
    required String code,
  }) async {
    if (code != validCode) {
      throw const AuthException(
        'That code has expired or is incorrect. Request a new one.',
      );
    }
    return _signIn(email);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    final failure = sendFailure;
    if (failure != null) throw failure;
    resetsSentTo.add(email);
  }

  @override
  Future<AuthUser> verifyPasswordReset({
    required String email,
    required String code,
  }) async {
    if (code != validResetCode) {
      throw const AuthException(
        'That reset code has expired or is incorrect. Request a new one.',
      );
    }
    return _signIn(email);
  }

  @override
  Future<void> updatePassword(String password) async {
    final email = user?.email;
    if (email == null) {
      throw const AuthException('Sign in before changing your password.');
    }
    passwords[email] = password;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    user = null;
    _controller.add(null);
  }

  AuthUser _signIn(String email) {
    final signedIn = AuthUser(id: 'user-${email.hashCode}', email: email);
    user = signedIn;
    _controller.add(signedIn);
    return signedIn;
  }

  Future<void> dispose() => _controller.close();
}
