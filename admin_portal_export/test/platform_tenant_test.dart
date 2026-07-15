import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop_platform_admin/src/tenants/domain/platform_tenant.dart';

void main() {
  test('tenant and summary RPC payloads map safely', () {
    final tenant = PlatformTenant.fromJson({
      'id': 'tenant-id',
      'shop_name': 'Shop',
      'business_type': 'retail',
      'status': 'active',
      'plan': 'starter',
      'branch_count': 2,
      'user_count': 3,
      'created_at': '2026-07-15T00:00:00Z',
    });
    final summary = TenantSummary.fromJson({
      'total_tenants': 5,
      'active_tenants': 4,
      'suspended_tenants': 1,
      'starter_tenants': 2,
      'business_tenants': 2,
      'enterprise_tenants': 1,
    });
    expect(tenant.branchCount, 2);
    expect(tenant.userCount, 3);
    expect(summary.total, 5);
    expect(summary.enterprise, 1);
  });
}
