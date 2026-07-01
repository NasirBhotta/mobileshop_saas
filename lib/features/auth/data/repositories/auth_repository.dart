import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ── Email/Password Login ──
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  // ── Email/Password Signup ──
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );

    // Signup ke turant baad users table mein basic row banao
    if (response.user != null) {
      await _client.from('users').insert({
        'id': response.user!.id,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'role': 'owner',
      });
    }

    return response;
  }

  // ── Google Sign In (Web + Mobile) ──
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.mobileshop://login-callback/',
    );
  }

  // ── OTP Send (future — Twilio setup ke baad active hoga) ──
  Future<void> sendOtp({required String phone}) {
    return _client.auth.signInWithOtp(phone: phone);
  }

  // ── OTP Verify ──
  Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;
}
