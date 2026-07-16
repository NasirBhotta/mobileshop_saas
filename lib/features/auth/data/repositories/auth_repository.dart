import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../onboarding/data/repositories/setup_flow_repository.dart';

class AuthRepository {
  final SupabaseClient _client = Supabase.instance.client;
  late final SetupFlowRepository _setupFlowRepository = SetupFlowRepository(
    client: _client,
  );

  // ── Email/Password Login ──
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user != null) {
      await _setupFlowRepository.ensureUserProfile(user: user);
    }
    return response;
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

    if (response.user != null && response.session != null) {
      await _setupFlowRepository.ensureUserProfile(
        user: response.user!,
        fullName: fullName,
        phone: phone,
      );
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

  Future<void> signOutLocally() =>
      _client.auth.signOut(scope: SignOutScope.local);

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> ensureUserProfile({
    required User user,
    String? fullName,
    String? phone,
  }) {
    return _setupFlowRepository.ensureUserProfile(
      user: user,
      fullName: fullName,
      phone: phone,
    );
  }
}
