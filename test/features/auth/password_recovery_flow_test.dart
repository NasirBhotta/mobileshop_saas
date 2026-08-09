import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'forgot and change password routes are wired without replacing staff setup',
    () {
      final router =
          File('lib/config/router/app_router.dart').readAsStringSync();
      final login =
          File(
            'lib/features/auth/presentation/screens/login_screen.dart',
          ).readAsStringSync();
      final settings =
          File(
            'lib/features/settings/presentation/screens/account_settings_screen.dart',
          ).readAsStringSync();

      expect(router, contains("path: '/forgot-password'"));
      expect(router, contains("path: '/reset-password'"));
      expect(router, contains("path: '/change-password'"));
      expect(router, contains("path: '/set-staff-password'"));
      expect(
        router.indexOf('passwordRecoveryRefresh.isRecovering'),
        lessThan(router.indexOf('final prefs = await SharedPreferences')),
      );
      expect(login, contains("context.push('/forgot-password')"));
      expect(settings, contains("context.push('/change-password')"));
    },
  );

  test('recovery email uses the registered cross-platform callback', () {
    final source =
        File(
          'lib/features/auth/presentation/screens/forgot_password_screen.dart',
        ).readAsStringSync();
    expect(source, contains('resetPasswordForEmail'));
    expect(source, contains('passwordRecoveryRedirectUrl()'));
  });

  test('recovery exit clears the temporary session', () {
    final source =
        File(
          'lib/features/auth/presentation/screens/password_form_screen.dart',
        ).readAsStringSync();

    expect(source, contains('Future<void> _cancelRecovery()'));
    expect(source, contains('passwordRecoveryRefreshProvider).complete()'));
    expect(source, contains('auth.signOut()'));
  });
}
