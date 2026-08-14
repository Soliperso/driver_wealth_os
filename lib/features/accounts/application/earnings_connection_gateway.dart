import 'dart:async';

import 'package:argyle_link_flutter/argyle_link.dart';
import 'package:argyle_link_flutter/link_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/work_platform.dart';

abstract interface class EarningsConnectionGateway {
  Future<ConnectionLaunchResult> connect(WorkPlatform platform);
}

enum ConnectionLaunchResult { connected, dismissed, setupRequired }

final class EarningsConnectionException implements Exception {
  const EarningsConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Keeps the UI honest until a server-issued connection session is available.
final class SetupRequiredConnectionGateway
    implements EarningsConnectionGateway {
  const SetupRequiredConnectionGateway();

  @override
  Future<ConnectionLaunchResult> connect(WorkPlatform platform) async {
    return ConnectionLaunchResult.setupRequired;
  }
}

final class SupabaseArgyleConnectionGateway
    implements EarningsConnectionGateway {
  const SupabaseArgyleConnectionGateway();

  @override
  Future<ConnectionLaunchResult> connect(WorkPlatform platform) async {
    try {
      final client = Supabase.instance.client;
      // Previously this signed in anonymously, which minted an unrecoverable
      // identity: the connected account and every imported row were lost for
      // good on a reinstall. The app now requires a real account before it
      // gets here, so a missing session is a bug rather than a prompt.
      if (client.auth.currentSession == null) {
        throw const EarningsConnectionException(
          'Sign in before connecting a work account.',
        );
      }

      final session = await _createSession(platform);

      // `ArgyleLink.start` resolves when the native Link UI is *presented*,
      // not when the driver finishes with it. Reading a flag straight after it
      // returned therefore always saw `false`, so a successful connection was
      // reported as a dismissal and the "Connected" badge was dead UI.
      //
      // The outcome is whatever the SDK's callbacks say, and this waits for
      // one of them.
      final outcome = Completer<ConnectionLaunchResult>();
      void finish(ConnectionLaunchResult result) {
        if (!outcome.isCompleted) outcome.complete(result);
      }

      await ArgyleLink.start(
        LinkConfig(
          userToken: session.userToken,
          sandbox: session.sandbox,
          onAccountConnected: (_) {
            unawaited(_syncEarnings());
            finish(ConnectionLaunchResult.connected);
          },
          // Closing after connecting must not downgrade the result, which is
          // why `finish` only honours the first call.
          onClose: () => finish(ConnectionLaunchResult.dismissed),
          onError: (_) => finish(ConnectionLaunchResult.dismissed),
          onTokenExpired: (updateToken) {
            unawaited(
              _createSession(platform)
                  .then((newSession) => updateToken(newSession.userToken))
                  // Without this the Link UI sits on an expired token forever.
                  .catchError((Object _) => finish(
                        ConnectionLaunchResult.dismissed,
                      )),
            );
          },
        ),
      );
      return outcome.future;
    } on EarningsConnectionException {
      rethrow;
    } catch (error) {
      // The previous catch discarded `error` entirely, so an expired session,
      // a 409 from the edge function, a malformed response and an Argyle
      // outage were indistinguishable to both the driver and the logs.
      throw EarningsConnectionException(_readable(error));
    }
  }

  static String _readable(Object error) {
    if (error is FunctionException) {
      return switch (error.status) {
        401 || 403 => 'Your session expired. Sign in again to connect.',
        409 => 'That account is not connected yet. Try connecting it again.',
        _ => 'The connection service is unavailable. Please try again shortly.',
      };
    }
    if (error is FormatException) {
      return 'The connection service returned something unexpected.';
    }
    if (error is AuthException) {
      return 'Your session expired. Sign in again to connect.';
    }
    return 'We couldn’t open the secure connection. Please try again.';
  }

  Future<_ConnectionSession> _createSession(WorkPlatform platform) async {
    final response = await Supabase.instance.client.functions.invoke(
      'create-connection-session',
      body: {'platform': platform.id},
    );
    final data = response.data;
    if (data is! Map || data['userToken'] is! String) {
      throw const FormatException('Invalid connection session');
    }
    return _ConnectionSession(
      userToken: data['userToken'] as String,
      sandbox: data['sandbox'] != false,
    );
  }

  Future<void> _syncEarnings() async {
    await Supabase.instance.client.functions.invoke('sync-earnings');
  }
}

final class _ConnectionSession {
  const _ConnectionSession({required this.userToken, required this.sandbox});

  final String userToken;
  final bool sandbox;
}
