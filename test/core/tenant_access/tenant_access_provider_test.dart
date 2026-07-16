import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/tenant_access/tenant_access_provider.dart';

void main() {
  test('suspended tenant is blocked regardless of status casing', () {
    expect(
      resolveTenantAccessState('SUSPENDED'),
      TenantAccessState.suspended,
    );
  });

  test('active and legacy missing status remain accessible', () {
    expect(resolveTenantAccessState('active'), TenantAccessState.active);
    expect(resolveTenantAccessState(null), TenantAccessState.active);
  });
}
