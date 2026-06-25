import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';

class AuthRepository {
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: normalizedEmail,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw const AuthException('Unable to sign in');
    }

    return UserModel(
      id: user.id,
      email: user.email ?? normalizedEmail,
      name: user.userMetadata?['name'] as String?,
    );
  }
}
