import '../models/user_model.dart';

class AuthRepository {
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    return UserModel(id: email, email: email);
  }
}
