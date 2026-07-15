import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop_platform_admin/src/addons/domain/platform_addon.dart';

void main() {
  test('add-on parses entitlement and assignment count', () {
    final addon = PlatformAddon.fromJson({
      'id': 'addon-id',
      'key': 'extra_users',
      'name': 'Extra users',
      'billing_type': 'per_unit',
      'price': 500,
      'is_active': true,
      'assigned_tenants': 3,
      'limit_key': 'users.count',
      'limit_increase': 5,
    });
    expect(addon.limitKey, 'users.count');
    expect(addon.limitIncrease, 5);
    expect(addon.assignedTenants, 3);
  });

  test('usage parses approaching and exceeded warning data', () {
    final usage = TenantUsage.fromJson({
      'limit_key': 'users.count',
      'warning_level': 'approaching',
      'used_value': 9,
      'effective_limit': 10,
      'usage_percent': 90,
      'addon_increase': 5,
      'plan_limit': 5,
      'override_limit': null,
    });
    expect(usage.warning, 'approaching');
    expect(usage.percent, 90);
    expect(usage.effective, usage.packageLimit! + usage.addonIncrease);
  });
}
