import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/accounts/data/repositories/accounts_repository.dart';
import 'package:mobileshop_saas/features/accounts/domain/account_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('enabled account features work', () async {
    await expectLater(
      AccountEntitlementGate(
        _evaluator(enabled: true),
      ).require('accounts.transfers'),
      completes,
    );
  });

  test('disabled account action is hidden and blocked', () async {
    expect(isEntitledActionVisible(false), isFalse);
    await expectLater(
      AccountEntitlementGate(
        _evaluator(enabled: false),
      ).require('accounts.transfers'),
      throwsA(isA<EntitlementDeniedException>()),
    );
  });

  test('direct account repository call cannot bypass entitlement', () async {
    final repository = AccountsRepository(
      client: SupabaseClient('http://localhost', 'test-anon-key'),
      entitlementEvaluator: _evaluator(enabled: false),
    );
    await expectLater(
      repository.fetchAccounts(),
      throwsA(
        isA<EntitlementDeniedException>().having(
          (error) => error.featureKey,
          'featureKey',
          'accounts.core',
        ),
      ),
    );
  });

  test('tenant override takes priority for accounts', () async {
    await expectLater(
      AccountEntitlementGate(
        _evaluator(enabled: false, overrideEnabled: true),
      ).require('accounts.transfers'),
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

  static const keys = ['accounts.core', 'accounts.transfers'];

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
