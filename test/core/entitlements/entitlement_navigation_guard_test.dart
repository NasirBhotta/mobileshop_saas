import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';

void main() {
  test('module and nested routes map to the same package feature', () {
    expect(requiredFeatureForLocation('/inventory'), 'inventory.access');
    expect(
      requiredFeatureForLocation('/inventory/categories'),
      'inventory.access',
    );
    expect(
      requiredFeatureForLocation('/reports/business/profit-loss'),
      'reports.business',
    );
    expect(requiredFeatureForLocation('/reports/sales'), 'reports.sales');
    expect(
      requiredFeatureForLocation('/reports/sales/schedules/new'),
      'reports.scheduled',
    );
    expect(requiredFeatureForLocation('/login'), isNull);
  });

  test('disabled package feature is denied without any owner bypass', () async {
    final evaluator = EntitlementEvaluator(
      dataSource: _FeatureDataSource(enabled: false),
    );
    expect(await evaluator.hasFeature('inventory.access'), isFalse);
  });

  test('cache invalidation refreshes changed package access', () async {
    final source = _FeatureDataSource(enabled: false);
    final evaluator = EntitlementEvaluator(dataSource: source);
    expect(await evaluator.hasFeature('inventory.access'), isFalse);
    source.enabled = true;
    expect(await evaluator.hasFeature('inventory.access'), isFalse);
    evaluator.overrideChanged('tenant-1');
    expect(await evaluator.hasFeature('inventory.access'), isTrue);
  });
}

class _FeatureDataSource implements EntitlementDataSource {
  bool enabled;
  _FeatureDataSource({required this.enabled});
  @override
  String? get currentUserId => 'owner-user';
  @override
  Future<TenantEntitlementContext?> loadTenantContext(String userId) async =>
      const TenantEntitlementContext(
        tenantId: 'tenant-1',
        compatibilityPlanKey: 'enterprise',
      );
  @override
  Future<TenantEntitlementSnapshot> loadSnapshot(String tenantId) async =>
      TenantEntitlementSnapshot(
        subscriptionPlanKey: 'custom-plan',
        planFeatures: [
          EntitlementFeatureValue(key: 'inventory.access', enabled: enabled),
        ],
      );
}
