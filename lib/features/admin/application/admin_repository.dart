import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/admin_models.dart';

abstract interface class AdminRepository {
  /// The client receives only a yes/no answer, never an editable role value.
  Future<bool> canAccessAdmin();

  Future<AdminOverview> loadOverview();

  Future<List<AdminUserSummary>> loadUsers({String query = ''});

  Future<void> setCloudAccess({required String userId, required bool enabled});
}

final class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

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
  Future<List<AdminUserSummary>> loadUsers({String query = ''}) async {
    final result = await _client.rpc(
      'admin_list_users',
      params: {
        'search_text': query.trim().isEmpty ? null : query.trim(),
        'limit_count': 100,
        'offset_count': 0,
      },
    );
    final rows = result is List ? result : const <Object?>[];
    return [
      for (final row in rows)
        if (row is Map) AdminUserSummary.fromJson(_map(row)),
    ];
  }

  @override
  Future<void> setCloudAccess({
    required String userId,
    required bool enabled,
  }) => _client.rpc(
    'admin_set_user_cloud_access',
    params: {'target_user_id': userId, 'enabled': enabled},
  );

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('The admin response was not an object');
    }
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
