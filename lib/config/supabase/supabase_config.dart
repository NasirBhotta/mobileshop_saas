class SupabaseConfig {
  const SupabaseConfig._();

  static const String _fallbackUrl = 'https://kwxqukkdrpiyjnxxccil.supabase.co';
  static const String _fallbackAnonKey =
      'sb_publishable_-C9FG1q6o3vQZOC5hkHN1A_2BJ6e9sB';

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _fallbackUrl,
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _fallbackAnonKey,
  );
}
