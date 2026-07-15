import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_shop_platform_admin/src/platform/domain/platform_analytics.dart';

void main() {
  test('analytics maps financial and distribution metrics', () {
    final value = PlatformAnalytics.fromJson({
      'total_tenants': 10,
      'active_tenants': 8,
      'suspended_tenants': 2,
      'monthly_revenue': 12500.5,
      'currency': 'PKR',
      'unpaid_invoice_count': 3,
      'unpaid_invoice_amount': 1500,
      'active_trials': 2,
      'upcoming_renewals': 4,
      'tenant_growth': [
        {'month': '2026-07', 'count': 3},
      ],
      'plan_distribution': [
        {'name': 'starter', 'count': 6},
      ],
      'feature_usage': [
        {'name': 'reports.export', 'count': 4},
      ],
      'addon_usage': [
        {'name': 'Extra users', 'count': 2},
      ],
    });
    expect(value.revenue, 12500.5);
    expect(value.plans.single.count, 6);
    expect(value.addons.single.name, 'Extra users');
  });
  test('settings map maintenance and billing defaults', () {
    final value = PlatformSettings.fromJson({
      'trial_duration_days': 14,
      'grace_period_days': 7,
      'default_billing_cycle': 'monthly',
      'default_currency': 'PKR',
      'support_email': 'support@example.com',
      'support_phone': null,
      'maintenance_mode': true,
      'maintenance_message': 'Upgrade',
    });
    expect(value.maintenance, isTrue);
    expect(value.trialDays, 14);
  });
}
