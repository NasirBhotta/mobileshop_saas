import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop_platform_admin/src/auth/domain/admin_access.dart';
import 'package:mobile_shop_platform_admin/src/routing/admin_access_guard.dart';

void main() {
  test('signed-out users are redirected to login', () {
    expect(
      adminRedirect(access: AdminAccess.signedOut, location: '/'),
      '/login',
    );
  });

  test('unauthorized authenticated users are denied', () {
    expect(
      adminRedirect(access: AdminAccess.accessDenied, location: '/'),
      '/access-denied',
    );
  });

  test('active platform admins can reach dashboard', () {
    expect(
      adminRedirect(access: AdminAccess.platformAdmin, location: '/'),
      isNull,
    );
  });

  test('resolved active admin leaves loading route', () {
    expect(
      adminRedirect(access: AdminAccess.platformAdmin, location: '/loading'),
      '/',
    );
  });
}
