import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 12);

  test('plan defaults resolve features and limits', () async {
    final source = _FakeEntitlementDataSource(
      snapshot: const TenantEntitlementSnapshot(
        subscriptionPlanKey: 'business',
        planFeatures: [
          EntitlementFeatureValue(key: 'reports.export', enabled: true),
        ],
        planLimits: [
          EntitlementLimitValue(key: 'expenses.history_days', value: 365),
        ],
      ),
    );
    final evaluator = EntitlementEvaluator(
      dataSource: source,
      clock: () => now,
    );

    expect(await evaluator.hasFeature('reports.export'), isTrue);
    expect(await evaluator.getLimit('expenses.history_days'), 365);
    expect((await evaluator.evaluateFeature('missing')).isEnabled, isFalse);
  });

  test('tenant overrides take priority over plan defaults', () async {
    final evaluator = EntitlementEvaluator(
      dataSource: _FakeEntitlementDataSource(
        snapshot: const TenantEntitlementSnapshot(
          subscriptionPlanKey: 'starter',
          planFeatures: [
            EntitlementFeatureValue(key: 'reports.export', enabled: false),
          ],
          featureOverrides: [
            EntitlementFeatureValue(key: 'reports.export', enabled: true),
          ],
          planLimits: [
            EntitlementLimitValue(key: 'expenses.history_days', value: 30),
          ],
          limitOverrides: [
            EntitlementLimitValue(key: 'expenses.history_days', value: 90),
          ],
        ),
      ),
      clock: () => now,
    );

    final feature = await evaluator.evaluateFeature('reports.export');
    final limit = await evaluator.evaluateLimit('expenses.history_days');
    expect(feature.isEnabled, isTrue);
    expect(feature.source, EntitlementValueSource.tenantOverride);
    expect(limit.value, 90);
    expect(limit.source, EntitlementValueSource.tenantOverride);
  });

  test('expired and inactive overrides are ignored', () async {
    final evaluator = EntitlementEvaluator(
      dataSource: _FakeEntitlementDataSource(
        snapshot: TenantEntitlementSnapshot(
          subscriptionPlanKey: 'starter',
          planFeatures: const [
            EntitlementFeatureValue(key: 'reports.export', enabled: false),
          ],
          featureOverrides: [
            EntitlementFeatureValue(
              key: 'reports.export',
              enabled: true,
              expiresAt: now.subtract(const Duration(minutes: 1)),
            ),
            const EntitlementFeatureValue(
              key: 'reports.export',
              enabled: true,
              isActive: false,
            ),
          ],
        ),
      ),
      clock: () => now,
    );

    final result = await evaluator.evaluateFeature('reports.export');
    expect(result.isEnabled, isFalse);
    expect(result.source, EntitlementValueSource.planDefault);
  });

  test('missing subscription falls back to tenants.plan', () async {
    final evaluator = EntitlementEvaluator(
      dataSource: _FakeEntitlementDataSource(
        compatibilityPlanKey: 'business',
        snapshot: const TenantEntitlementSnapshot(subscriptionPlanKey: null),
      ),
      clock: () => now,
    );

    final result = await evaluator.evaluateFeature('reports.export');
    expect(result.isEnabled, isTrue);
    expect(result.source, EntitlementValueSource.compatibilityPlanFallback);
    expect(await evaluator.getLimit('expenses.history_days'), 365);
  });

  test('module access enables missing granular feature keys', () async {
    final evaluator = EntitlementEvaluator(
      dataSource: _FakeEntitlementDataSource(
        snapshot: const TenantEntitlementSnapshot(
          subscriptionPlanKey: 'starter',
          planFeatures: [
            EntitlementFeatureValue(key: 'expenses.access', enabled: true),
            EntitlementFeatureValue(key: 'accounts.access', enabled: true),
            EntitlementFeatureValue(key: 'repairs.access', enabled: true),
          ],
        ),
      ),
      clock: () => now,
    );

    expect(
      await hasFeatureWithCompatibility(evaluator, 'expenses.core'),
      isTrue,
    );
    expect(
      await hasFeatureWithCompatibility(evaluator, 'accounts.core'),
      isTrue,
    );
    expect(
      await hasFeatureWithCompatibility(evaluator, 'repairs.tickets'),
      isTrue,
    );
    expect(
      await hasFeatureWithCompatibility(evaluator, 'repairs.imei_linking'),
      isTrue,
    );
  });

  test(
    'cache invalidates after subscription, plan, and override changes',
    () async {
      final source = _FakeEntitlementDataSource(
        snapshot: const TenantEntitlementSnapshot(
          subscriptionPlanKey: 'starter',
          planFeatures: [
            EntitlementFeatureValue(key: 'reports.export', enabled: false),
          ],
        ),
      );
      final evaluator = EntitlementEvaluator(
        dataSource: source,
        clock: () => now,
      );

      expect(
        (await evaluator.evaluateFeature('reports.export')).fromCache,
        isFalse,
      );
      expect(
        (await evaluator.evaluateFeature('reports.export')).fromCache,
        isTrue,
      );
      expect(source.loadCount, 1);

      evaluator.subscriptionChanged('tenant-1');
      await evaluator.hasFeature('reports.export');
      evaluator.overrideChanged('tenant-1');
      await evaluator.hasFeature('reports.export');
      evaluator.planChanged();
      await evaluator.hasFeature('reports.export');
      expect(source.loadCount, 4);

      evaluator.invalidateAll();
      await evaluator.hasFeature('reports.export');
      expect(source.loadCount, 5);
    },
  );

  test(
    'concurrent feature checks share one context and snapshot load',
    () async {
      final source = _FakeEntitlementDataSource(
        snapshot: const TenantEntitlementSnapshot(
          subscriptionPlanKey: 'starter',
          planFeatures: [
            EntitlementFeatureValue(key: 'inventory.access', enabled: true),
          ],
        ),
      );
      final evaluator = EntitlementEvaluator(dataSource: source);

      final results = await Future.wait([
        for (var index = 0; index < 12; index++)
          evaluator.hasFeature('inventory.access'),
      ]);

      expect(results, everyElement(isTrue));
      expect(source.contextLoadCount, 1);
      expect(source.loadCount, 1);

      await evaluator.hasFeature('inventory.access');
      expect(source.contextLoadCount, 1);
      expect(source.loadCount, 1);
    },
  );
}

class _FakeEntitlementDataSource implements EntitlementDataSource {
  String? userId = 'user-1';
  String tenantId = 'tenant-1';
  String? compatibilityPlanKey;
  TenantEntitlementSnapshot snapshot;
  int loadCount = 0;
  int contextLoadCount = 0;

  _FakeEntitlementDataSource({
    required this.snapshot,
    this.compatibilityPlanKey = 'starter',
  });

  @override
  String? get currentUserId => userId;

  @override
  Future<TenantEntitlementContext?> loadTenantContext(String userId) async {
    contextLoadCount++;
    return TenantEntitlementContext(
      tenantId: tenantId,
      compatibilityPlanKey: compatibilityPlanKey,
    );
  }

  @override
  Future<TenantEntitlementSnapshot> loadSnapshot(String tenantId) async {
    loadCount++;
    return snapshot;
  }
}
