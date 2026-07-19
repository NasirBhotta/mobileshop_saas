import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/features/inventory/data/repositories/inventory_repository.dart';
import 'package:mobileshop_saas/features/inventory/domain/inventory_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';

void main() {
  test('enabled inventory feature passes the execution gate', () async {
    final gate = InventoryEntitlementGate(_evaluator(planEnabled: true));
    await expectLater(gate.require('inventory.csv_import'), completes);
  });

  test('disabled inventory feature is blocked', () async {
    final gate = InventoryEntitlementGate(_evaluator(planEnabled: false));
    await expectLater(
      gate.require('inventory.bulk_pricing'),
      throwsA(isA<EntitlementDeniedException>()),
    );
  });

  test('disabled feature action is hidden while enabled action remains', () {
    expect(isEntitledActionVisible(false), isFalse);
    expect(isEntitledActionVisible(true), isTrue);
    expect(isEntitledActionVisible(null), isTrue);
  });

  test('direct repository call cannot bypass entitlement', () async {
    final repository = InventoryRepository(
      client: SupabaseClient('http://localhost', 'test-anon-key'),
      entitlementEvaluator: _evaluator(planEnabled: false),
    );
    await expectLater(
      repository.importFromCsv(const <List<dynamic>>[]),
      throwsA(
        isA<EntitlementDeniedException>().having(
          (error) => error.featureKey,
          'featureKey',
          'inventory.csv_import',
        ),
      ),
    );
  });

  test('tenant override takes priority over disabled plan feature', () async {
    final gate = InventoryEntitlementGate(
      _evaluator(planEnabled: false, overrideEnabled: true),
    );
    await expectLater(gate.require('inventory.imei_tracking'), completes);
  });

  test('undefined sensitive inventory feature fails closed', () async {
    final evaluator = EntitlementEvaluator(
      dataSource: const _LegacyInventoryDataSource(),
    );
    await expectLater(
      InventoryEntitlementGate(
        evaluator,
      ).require('inventory.stock_adjustments'),
      throwsA(isA<EntitlementDeniedException>()),
    );
    expect(
      await hasFeatureWithCompatibility(
        evaluator,
        'inventory.stock_adjustments',
      ),
      isFalse,
    );
  });
}

EntitlementEvaluator _evaluator({
  required bool planEnabled,
  bool? overrideEnabled,
}) => EntitlementEvaluator(
  dataSource: _InventoryEntitlementDataSource(
    planEnabled: planEnabled,
    overrideEnabled: overrideEnabled,
  ),
);

class _InventoryEntitlementDataSource implements EntitlementDataSource {
  final bool planEnabled;
  final bool? overrideEnabled;
  const _InventoryEntitlementDataSource({
    required this.planEnabled,
    this.overrideEnabled,
  });
  @override
  String? get currentUserId => 'owner-user';
  @override
  Future<TenantEntitlementContext?> loadTenantContext(String userId) async =>
      const TenantEntitlementContext(
        tenantId: 'tenant-1',
        compatibilityPlanKey: 'enterprise',
      );
  @override
  Future<TenantEntitlementSnapshot> loadSnapshot(String tenantId) async {
    const keys = [
      'inventory.csv_import',
      'inventory.bulk_pricing',
      'inventory.imei_tracking',
      'inventory.stock_adjustments',
    ];
    return TenantEntitlementSnapshot(
      subscriptionPlanKey: 'test-plan',
      planFeatures: [
        for (final key in keys)
          EntitlementFeatureValue(key: key, enabled: planEnabled),
      ],
      featureOverrides:
          overrideEnabled == null
              ? const []
              : [
                for (final key in keys)
                  EntitlementFeatureValue(key: key, enabled: overrideEnabled!),
              ],
    );
  }
}

class _LegacyInventoryDataSource implements EntitlementDataSource {
  const _LegacyInventoryDataSource();
  @override
  String? get currentUserId => 'owner-user';
  @override
  Future<TenantEntitlementContext?> loadTenantContext(String userId) async =>
      const TenantEntitlementContext(
        tenantId: 'tenant-1',
        compatibilityPlanKey: 'starter',
      );
  @override
  Future<TenantEntitlementSnapshot> loadSnapshot(String tenantId) async =>
      const TenantEntitlementSnapshot(
        subscriptionPlanKey: 'starter',
        planFeatures: [
          EntitlementFeatureValue(key: 'inventory.access', enabled: true),
        ],
      );
}
