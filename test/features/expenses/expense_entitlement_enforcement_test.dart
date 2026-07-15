import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/expenses/data/repositories/expense_repository.dart';
import 'package:mobileshop_saas/features/expenses/domain/expense_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('enabled expense features work', () async {
    await expectLater(
      ExpenseEntitlementGate(
        _evaluator(enabled: true),
      ).require('expenses.recurring'),
      completes,
    );
  });

  test('disabled expense action is hidden and blocked', () async {
    expect(isEntitledActionVisible(false), isFalse);
    await expectLater(
      ExpenseEntitlementGate(
        _evaluator(enabled: false),
      ).require('expenses.receipts'),
      throwsA(isA<EntitlementDeniedException>()),
    );
  });

  test('direct expense repository call cannot bypass entitlement', () async {
    final repository = ExpenseRepository(
      client: SupabaseClient('http://localhost', 'test-anon-key'),
      entitlements: _evaluator(enabled: false),
    );
    await expectLater(
      repository.fetchCategories(),
      throwsA(
        isA<EntitlementDeniedException>().having(
          (error) => error.featureKey,
          'featureKey',
          'expenses.core',
        ),
      ),
    );
  });

  test('tenant override takes priority for expenses', () async {
    await expectLater(
      ExpenseEntitlementGate(
        _evaluator(enabled: false, overrideEnabled: true),
      ).require('expenses.reporting'),
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

  static const keys = [
    'expenses.core',
    'expenses.receipts',
    'expenses.recurring',
    'expenses.reporting',
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
