import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/repairs/data/repositories/repair_repository.dart';
import 'package:mobileshop_saas/features/repairs/domain/repair_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('enabled repair feature works', () async {
    await expectLater(
      RepairEntitlementGate(
        _evaluator(enabled: true),
      ).require('repairs.tickets'),
      completes,
    );
  });

  test('disabled repair action is hidden and blocked', () async {
    expect(isEntitledActionVisible(false), isFalse);
    await expectLater(
      RepairEntitlementGate(
        _evaluator(enabled: false),
      ).require('repairs.imei_linking'),
      throwsA(isA<EntitlementDeniedException>()),
    );
  });

  test('direct repair repository call cannot bypass entitlement', () async {
    final repository = RepairRepository(
      client: SupabaseClient('http://localhost', 'test-anon-key'),
      entitlementEvaluator: _evaluator(enabled: false),
    );
    await expectLater(
      repository.fetchRepairTickets(),
      throwsA(
        isA<EntitlementDeniedException>().having(
          (error) => error.featureKey,
          'featureKey',
          'repairs.tickets',
        ),
      ),
    );
  });

  test('tenant override takes priority for repairs', () async {
    await expectLater(
      RepairEntitlementGate(
        _evaluator(enabled: false, overrideEnabled: true),
      ).require('repairs.imei_linking'),
      completes,
    );
  });
}

EntitlementEvaluator _evaluator({
  required bool enabled,
  bool? overrideEnabled,
}) => EntitlementEvaluator(dataSource: _DataSource(enabled, overrideEnabled));

class _DataSource implements EntitlementDataSource {
  final bool enabled;
  final bool? overrideEnabled;
  const _DataSource(this.enabled, this.overrideEnabled);

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
    const keys = ['repairs.tickets', 'repairs.imei_linking'];
    return TenantEntitlementSnapshot(
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
                  EntitlementFeatureValue(key: key, enabled: overrideEnabled!),
              ],
    );
  }
}
