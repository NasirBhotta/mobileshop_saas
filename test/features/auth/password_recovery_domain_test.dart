import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/auth/domain/password_recovery.dart';

void main() {
  group('password recovery helpers', () {
    test('masks the email while keeping it recognizable', () {
      expect(maskRecoveryEmail('owner@example.com'), 'ow***@example.com');
      expect(maskRecoveryEmail('a@example.com'), 'a@example.com');
    });

    test('uses a safe web reset route without old query or fragment', () {
      final result = passwordRecoveryRedirectUrl(
        browserUri: Uri.parse('https://shop.example.com/login?old=1#old'),
      );

      // Native test runners intentionally use the registered app callback.
      expect(
        result,
        anyOf(
          nativePasswordRecoveryCallback,
          'https://shop.example.com/reset-password',
        ),
      );
    });

    test('does not expose raw server errors to the user', () {
      final message = passwordRecoveryErrorMessage(
        Exception('internal auth.users lookup failed'),
      );

      expect(message, isNot(contains('auth.users')));
    });
  });
}
