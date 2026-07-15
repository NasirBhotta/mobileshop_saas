import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/admin_auth_repository.dart';
import '../domain/admin_access.dart';

final adminAuthRepositoryProvider = Provider<AdminAuthRepository>((ref) {
  return AdminAuthRepository();
});

final adminAuthStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(adminAuthRepositoryProvider).authStateChanges;
});

final adminAccessProvider = FutureProvider<AdminAccess>((ref) async {
  ref.watch(adminAuthStateProvider);
  final repository = ref.watch(adminAuthRepositoryProvider);
  if (repository.currentUser == null) return AdminAccess.signedOut;
  return await repository.hasActivePlatformAdminAccess()
      ? AdminAccess.platformAdmin
      : AdminAccess.accessDenied;
});

final adminLoginControllerProvider =
    AsyncNotifierProvider<AdminLoginController, void>(AdminLoginController.new);

class AdminLoginController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(adminAuthRepositoryProvider)
          .signIn(email: email, password: password);
      ref.invalidate(adminAccessProvider);
      final access = await ref.read(adminAccessProvider.future);
      state = const AsyncData(null);
      return access == AdminAccess.platformAdmin;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    await ref.read(adminAuthRepositoryProvider).signOut();
    ref.invalidate(adminAccessProvider);
    state = const AsyncData(null);
  }
}
