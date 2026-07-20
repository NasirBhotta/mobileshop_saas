import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth lifecycle recreates tenant and entitlement realtime channels', () {
    final source =
        File(
          'lib/features/auth/presentation/providers/auth_provider.dart',
        ).readAsStringSync();

    expect(source, contains('ref.invalidate(tenantAccessRealtimeProvider);'));
    expect(
      source,
      contains('ref.invalidate(entitlementRealtimeRefreshProvider);'),
    );
  });
}
