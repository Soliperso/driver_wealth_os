abstract final class BackendConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const _legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const incomeSyncEnabled = bool.fromEnvironment(
    'INCOME_SYNC_ENABLED',
    defaultValue: false,
  );

  static String get supabasePublishableKey => _supabasePublishableKey.isNotEmpty
      ? _supabasePublishableKey
      : _legacyAnonKey;

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
