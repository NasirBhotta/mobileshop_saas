abstract final class AdminPortalConfig {
  static const String _fallbackUrl = 'https://kwxqukkdrpiyjnxxccil.supabase.co';
  static const String _fallbackAnonKey =
      'sb_publishable_-C9FG1q6o3vQZOC5hkHN1A_2BJ6e9sB';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _fallbackUrl,
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _fallbackAnonKey,
  );

  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be supplied with --dart-define.',
      );
    }
  }
}
