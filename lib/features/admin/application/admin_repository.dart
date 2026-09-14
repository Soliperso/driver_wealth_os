import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/admin_models.dart';

abstract interface class AdminRepository {
  /// The client receives only a yes/no answer, never an editable role value.
  Future<bool> canAccessAdmin();

  Future<AdminOverview> loadOverview();

  /// One page of drivers matching [query] and [filter].
  ///
  /// Both the search and the status filter are applied by the control plane
  /// rather than here, so paging stays correct: filtering a page after it
  /// arrives would answer "the paused drivers on this page" instead of "the
  /// paused drivers".
  Future<AdminUserPage> loadUsers({
    String query,
    AdminAccessFilter filter,
    int limit,
    int offset,
  });

  Future<void> setCloudAccess({required String userId, required bool enabled});

  /// The most recent access changes, newest first.
  Future<List<AdminAction>> loadRecentActions();
}

final class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Deliberately smaller than the control plane's 200-row ceiling. A page is
  /// something an owner scrolls, and the rest is one tap away.
  static const pageSize = 50;

  @override
  Future<bool> canAccessAdmin() async {
    final result = await _client.rpc('is_platform_admin');
    return result == true;
  }

  @override
  Future<AdminOverview> loadOverview() async {
    final result = await _client.rpc('admin_dashboard_overview');
    return AdminOverview.fromJson(_map(result));
  }

  @override
  Future<AdminUserPage> loadUsers({
    String query = '',
    AdminAccessFilter filter = AdminAccessFilter.all,
    int limit = pageSize,
    int offset = 0,
  }) async {
    final result = await _client.rpc(
      'admin_list_users',
      params: {
        'search_text': query.trim().isEmpty ? null : query.trim(),
        'limit_count': limit,
        'offset_count': offset,
        'status_filter': filter.id,
      },
    );
    return AdminUserPage.fromJson(result);
  }

  @override
  Future<void> setCloudAccess({
    required String userId,
    required bool enabled,
  }) => _client.rpc(
    'admin_set_user_cloud_access',
    params: {'target_user_id': userId, 'enabled': enabled},
  );

  @override
  Future<List<AdminAction>> loadRecentActions() async {
    final result = await _client.rpc(
      'admin_recent_actions',
      params: {'limit_count': 20},
    );
    final rows = result is List ? result : const <Object?>[];
    return [
      for (final row in rows)
        if (row is Map) AdminAction.fromJson(_map(row)),
    ];
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('The admin response was not an object');
    }
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
