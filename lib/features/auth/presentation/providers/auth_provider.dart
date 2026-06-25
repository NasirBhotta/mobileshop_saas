import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/user_entity.dart';

final authProvider = NotifierProvider<AuthProvider, AuthState>(
  AuthProvider.new,
);

class AuthState {
  const AuthState({this.user, this.isLoading = false, this.errorMessage});

  final UserEntity? user;
  final bool isLoading;
  final String? errorMessage;

  AuthState copyWith({
    UserEntity? user,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AuthProvider extends Notifier<AuthState> {
  final AuthRepository _repository = AuthRepository();

  @override
  AuthState build() {
    return const AuthState();
  }

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final user = await _repository.signIn(email: email, password: password);
      state = state.copyWith(user: user, isLoading: false);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to sign in',
      );
    }
  }
}
