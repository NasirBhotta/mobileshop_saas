import 'package:flutter/material.dart';

import '../../features/auth/presentation/screens/login_screen.dart';

class AppRouter {
  const AppRouter._();

  static const String login = '/login';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) {
        switch (settings.name) {
          case login:
          default:
            return const LoginScreen();
        }
      },
    );
  }
}
