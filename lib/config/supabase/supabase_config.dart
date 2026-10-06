import 'package:flutter/foundation.dart';

class SupabaseConfig {
  const SupabaseConfig._();

  static const String _fallbackUrl = 'https://kwxqukkdrpiyjnxxccil.supabase.co';
  static const String _fallbackAnonKey =
      'sb_publishable_-C9FG1q6o3vQZOC5hkHN1A_2BJ6e9sB';

  static String get url {
    const configured = String.fromEnvironment('SUPABASE_URL');
    if (kIsWeb && configured.isEmpty) {
      throw StateError('SUPABASE_URL must be explicitly set for web builds.');
    }
    return configured.isEmpty ? _fallbackUrl : configured;
  }

  static String get anonKey {
    const configured = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (kIsWeb && configured.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY must be explicitly set for web builds.',
      );
    }
    return configured.isEmpty ? _fallbackAnonKey : configured;
  }
}
