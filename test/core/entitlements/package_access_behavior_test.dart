import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';

void main() {
  group('Package Patch 5 compatibility behaviour', () {
    for (final plan in const ['starter', 'business', 'enterprise']) {
      test('$plan report export and scheduling', () async {
        final evaluator = _fallbackEvaluator(plan);
        expect(await evaluator.hasFeature('reports.export'), isTrue);
        expect(
          await evaluator.hasFeature('reports.scheduling'),
          plan == 'starter' ? isFalse : isTrue,
        );
      });
    }

    test('expense history remains 30, 365, and unlimited', () async {
      expect(
        await _fallbackEvaluator('starter').getLimit('expenses.history_days'),
        30,
      );
      expect(
        await _fallbackEvaluator('business').getLimit('expenses.history_days'),
        365,
      );
      expect(
        await _fallbackEvaluator(
          'enterprise',
        ).getLimit('expenses.history_days'),
        isNull,
      );
    });

    test('tenant feature and limit overrides take priority', () async {
      final evaluator = EntitlementEvaluator(
        dataSource: _PackageDataSource(
          planKey: 'starter',
          snapshot: const TenantEntitlementSnapshot(
            subscriptionPlanKey: 'starter',
            planFeatures: [
              EntitlementFeatureValue(key: 'reports.export', enabled: false),
              EntitlementFeatureValue(
                key: 'reports.scheduling',
                enabled: false,
              ),
            ],
            featureOverrides: [
              EntitlementFeatureValue(key: 'reports.export', enabled: true),
              EntitlementFeatureValue(key: 'reports.scheduling', enabled: true),
            ],
            planLimits: [
              EntitlementLimitValue(key: 'expenses.history_days', value: 30),
            ],
            limitOverrides: [
              EntitlementLimitValue(key: 'expenses.history_days', value: 120),
            ],
          ),
        ),
      );

      expect(await evaluator.hasFeature('reports.export'), isTrue);
      expect(await evaluator.hasFeature('reports.scheduling'), isTrue);
      expect(await evaluator.getLimit('expenses.history_days'), 120);
    });
  });
}

EntitlementEvaluator _fallbackEvaluator(String planKey) => EntitlementEvaluator(
  dataSource: _PackageDataSource(
    planKey: planKey,
    snapshot: const TenantEntitlementSnapshot(subscriptionPlanKey: null),
  ),
);

class _PackageDataSource implements EntitlementDataSource {
  final String planKey;
  final TenantEntitlementSnapshot snapshot;

  const _PackageDataSource({required this.planKey, required this.snapshot});

  @override
  String? get currentUserId => 'package-user';

  @override
  Future<TenantEntitlementContext?> loadTenantContext(String userId) async =>
      TenantEntitlementContext(
        tenantId: 'package-tenant-$planKey',
        compatibilityPlanKey: planKey,
      );

  @override
  Future<TenantEntitlementSnapshot> loadSnapshot(String tenantId) async =>
      snapshot;
}
