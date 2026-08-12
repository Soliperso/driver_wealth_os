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
      var accountConnected = false;
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) {
        await client.auth.signInAnonymously();
      }

      final session = await _createSession(platform);
      await ArgyleLink.start(
        LinkConfig(
          userToken: session.userToken,
          sandbox: session.sandbox,
          onAccountConnected: (_) {
            accountConnected = true;
            unawaited(_syncEarnings());
          },
          onTokenExpired: (updateToken) {
            unawaited(
              _createSession(
                platform,
              ).then((newSession) => updateToken(newSession.userToken)),
            );
          },
        ),
      );
      return accountConnected
          ? ConnectionLaunchResult.connected
          : ConnectionLaunchResult.dismissed;
    } catch (error) {
      throw EarningsConnectionException(
        'We couldn’t open the secure connection. Please try again.',
      );
    }
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
