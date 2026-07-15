import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAuthRepository {
  final SupabaseClient _client;

  AdminAuthRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<bool> hasActivePlatformAdminAccess() async {
    if (currentUser == null) return false;
    final result = await _client.rpc('is_active_platform_admin');
    return result == true;
  }
}
