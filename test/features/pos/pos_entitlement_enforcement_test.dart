import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/pos/data/repositories/pos_repository.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('enabled POS feature passes execution gate', () async {
    await expectLater(
      PosEntitlementGate(_entitlements(enabled: true)).require('pos.checkout'),
      completes,
    );
  });

  test('disabled POS actions are hidden and blocked', () async {
    expect(isEntitledActionVisible(false), isFalse);
    await expectLater(
      PosEntitlementGate(
        _entitlements(enabled: false),
      ).require('pos.discounts'),
      throwsA(isA<EntitlementDeniedException>()),
    );
  });

  test('direct checkout repository call cannot bypass entitlement', () async {
    final repository = PosRepository(
      client: SupabaseClient('http://localhost', 'test-anon-key'),
      permissions: PermissionEvaluator(dataSource: _PermissionDataSource()),
      entitlementEvaluator: _entitlements(enabled: false),
    );
    await expectLater(
      repository.checkout(items: const [], payments: const []),
      throwsA(
        isA<EntitlementDeniedException>().having(
          (error) => error.featureKey,
          'featureKey',
          'pos.checkout',
        ),
      ),
    );
  });

  test(
    'tenant override takes priority over disabled POS plan feature',
    () async {
      await expectLater(
        PosEntitlementGate(
          _entitlements(enabled: false, overrideEnabled: true),
        ).require('pos.returns'),
        completes,
      );
    },
  );

  test('only safe legacy POS checkout inherits pos.access', () async {
    final evaluator = EntitlementEvaluator(
      dataSource: const _LegacyPosDataSource(),
    );
    await expectLater(
      PosEntitlementGate(evaluator).require('pos.returns'),
      throwsA(isA<EntitlementDeniedException>()),
    );
    expect(
      await hasFeatureWithCompatibility(evaluator, 'pos.checkout'),
      isTrue,
    );
  });
}

EntitlementEvaluator _entitlements({
  required bool enabled,
  bool? overrideEnabled,
}) => EntitlementEvaluator(
  dataSource: _EntitlementDataSource(enabled, overrideEnabled),
);

class _EntitlementDataSource implements EntitlementDataSource {
  final bool enabled;
  final bool? overrideEnabled;
  const _EntitlementDataSource(this.enabled, this.overrideEnabled);
  static const keys = [
    'pos.checkout',
    'pos.discounts',
    'pos.returns',
    'pos.credit_sales',
    'pos.receipt_printing',
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
          for (final key in keys)
            EntitlementFeatureValue(key: key, enabled: enabled),
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

class _PermissionDataSource implements PermissionDataSource {
  @override
  String? get currentUserId => 'owner-user';
  @override
  Future<String?> loadTenantId(String userId) async => 'tenant-1';
  @override
  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  }) async => const [];
}

class _LegacyPosDataSource implements EntitlementDataSource {
  const _LegacyPosDataSource();
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
          EntitlementFeatureValue(key: 'pos.access', enabled: true),
        ],
      );
}
