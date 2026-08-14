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

  /// When set, [sendCode] throws it — the delivery failures a driver actually
  /// hits: rate limits, bad addresses, no connection.
  AuthException? sendFailure;

  var sentTo = <String>[];
  var signOutCount = 0;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> get changes => _controller.stream;

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
    final signedIn = AuthUser(id: 'user-${email.hashCode}', email: email);
    user = signedIn;
    _controller.add(signedIn);
    return signedIn;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    user = null;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();
}
