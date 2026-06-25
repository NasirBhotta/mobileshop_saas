import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/user_entity.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? repository})
    : _repository = repository ?? AuthRepository();

  final AuthRepository _repository;

  UserEntity? user;
  bool isLoading = false;
  String? errorMessage;

  Future<void> signIn({required String email, required String password}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      user = await _repository.signIn(email: email, password: password);
    } catch (_) {
      errorMessage = 'Unable to sign in';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
