import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
      return AuthController(ref.watch(authRepositoryProvider));
    });

final authListenerProvider = StreamProvider<void>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);

  await for (final authState in repo.authStateChanges) {
    // Sirf pehli baar sign in pe (email verify ke baad)
    if (authState.event == AuthChangeEvent.signedIn) {
      final user = authState.session?.user;
      if (user == null) continue;

      // Check karo users table mein already hai ya nahi
      final existing =
          await Supabase.instance.client
              .from('users')
              .select('id')
              .eq('id', user.id)
              .maybeSingle();

      // Nahi hai toh insert karo
      if (existing == null) {
        await Supabase.instance.client.from('users').insert({
          'id': user.id,
          'full_name': user.userMetadata?['full_name'] ?? '',
          'email': user.email ?? '',
          'phone': user.userMetadata?['phone'] ?? '',
          'role': 'owner',
        });
      }
    }
  }
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  final AuthRepository _repository;

  AuthController(this._repository) : super(const AsyncData(null));

  void clearStatus() {
    state = const AsyncData(null);
  }

  Future<bool> login({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      await _repository.signInWithPassword(email: email, password: password);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> signup({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
      );
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> loginWithGoogle() async {
    state = const AsyncLoading();
    try {
      await _repository.signInWithGoogle();
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
