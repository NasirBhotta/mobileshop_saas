import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/suppliers/data/repositories/procurement_repository.dart';
import 'package:mobileshop_saas/features/suppliers/domain/procurement_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('enabled procurement feature works', () async {
    await expectLater(
      ProcurementEntitlementGate(
        _evaluator(specificEnabled: true),
      ).require('procurement.suppliers'),
      completes,
    );
  });

  test('disabled procurement action is hidden and blocked', () async {
    expect(isEntitledActionVisible(false), isFalse);
    await expectLater(
      ProcurementEntitlementGate(
        _evaluator(specificEnabled: false),
      ).require('procurement.goods_receipts'),
      throwsA(isA<EntitlementDeniedException>()),
    );
  });

  test(
    'direct procurement repository call cannot bypass entitlement',
    () async {
      final repository = ProcurementRepository(
        client: SupabaseClient('http://localhost', 'test-anon-key'),
        entitlementEvaluator: _evaluator(specificEnabled: false),
      );
      await expectLater(
        repository.fetchSuppliers(),
        throwsA(
          isA<EntitlementDeniedException>().having(
            (error) => error.featureKey,
            'featureKey',
            'procurement.suppliers',
          ),
        ),
      );
    },
  );

  test('tenant override takes priority for procurement', () async {
    await expectLater(
      ProcurementEntitlementGate(
        _evaluator(specificEnabled: false, overrideEnabled: true),
      ).require('procurement.supplier_payments'),
      completes,
    );
  });

  test(
    'current plans retain procurement through compatibility feature',
    () async {
      await expectLater(
        ProcurementEntitlementGate(
          _evaluator(specificEnabled: null, legacyEnabled: true),
        ).require('procurement.purchase_orders'),
        completes,
      );
    },
  );
}

EntitlementEvaluator _evaluator({
  required bool? specificEnabled,
  bool legacyEnabled = true,
  bool? overrideEnabled,
}) => EntitlementEvaluator(
  dataSource: _DataSource(specificEnabled, legacyEnabled, overrideEnabled),
);

class _DataSource implements EntitlementDataSource {
  final bool? specificEnabled;
  final bool legacyEnabled;
  final bool? overrideEnabled;
  const _DataSource(
    this.specificEnabled,
    this.legacyEnabled,
    this.overrideEnabled,
  );

  static const keys = [
    'procurement.suppliers',
    'procurement.purchase_orders',
    'procurement.goods_receipts',
    'procurement.supplier_payments',
  ];

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
        subscriptionPlanKey: 'test-plan',
        planFeatures: [
          const EntitlementFeatureValue(key: 'suppliers.access', enabled: true),
          const EntitlementFeatureValue(key: 'purchases.access', enabled: true),
          EntitlementFeatureValue(
            key: 'purchases.procurement',
            enabled: legacyEnabled,
          ),
          if (specificEnabled != null)
            for (final key in keys)
              EntitlementFeatureValue(key: key, enabled: specificEnabled!),
        ],
        featureOverrides:
            overrideEnabled == null
                ? const []
                : [
                  for (final key in keys)
                    EntitlementFeatureValue(
                      key: key,
                      enabled: overrideEnabled!,
                    ),
                ],
      );
}
