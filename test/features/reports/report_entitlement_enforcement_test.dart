import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_provider.dart';
import 'package:mobileshop_saas/features/reports/data/repositories/sales_report_repository.dart';
import 'package:mobileshop_saas/features/reports/domain/report_entitlement_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('enabled sales and business reports work', () async {
    final gate = ReportEntitlementGate(_evaluator(plan: 'business'));
    await expectLater(gate.require('reports.sales'), completes);
    await expectLater(gate.require('reports.business'), completes);
  });

  test('Starter can export but cannot schedule by default', () async {
    final gate = ReportEntitlementGate(_evaluator(plan: 'starter'));
    await expectLater(gate.require('reports.export'), completes);
    await expectLater(
      gate.require('reports.scheduled'),
      throwsA(isA<EntitlementDeniedException>()),
    );
    expect(isEntitledActionVisible(false), isFalse);
  });

  for (final plan in const ['business', 'enterprise']) {
    test('$plan can export and schedule', () async {
      final gate = ReportEntitlementGate(_evaluator(plan: plan));
      await expectLater(gate.require('reports.export'), completes);
      await expectLater(gate.require('reports.scheduled'), completes);
    });
  }

  test('disabled export cannot be bypassed through repository call', () async {
    final repository = SalesReportRepository(
      client: SupabaseClient('http://localhost', 'test-anon-key'),
      permissions: PermissionEvaluator(dataSource: _PermissionDataSource()),
      entitlements: _evaluator(plan: 'starter', exportOverride: false),
    );
    await expectLater(
      repository.buildCsvExport(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
      ),
      throwsA(
        isA<EntitlementDeniedException>().having(
          (error) => error.featureKey,
          'featureKey',
          'reports.export',
        ),
      ),
    );
  });

  test('tenant override takes priority', () async {
    final gate = ReportEntitlementGate(
      _evaluator(plan: 'starter', exportOverride: true, scheduleOverride: true),
    );
    await expectLater(gate.require('reports.export'), completes);
    await expectLater(gate.require('reports.scheduled'), completes);
  });
}

EntitlementEvaluator _evaluator({
  required String plan,
  bool? exportOverride,
  bool? scheduleOverride,
}) => EntitlementEvaluator(
  dataSource: _DataSource(plan, exportOverride, scheduleOverride),
);

class _DataSource implements EntitlementDataSource {
  final String plan;
  final bool? exportOverride;
  final bool? scheduleOverride;
  const _DataSource(this.plan, this.exportOverride, this.scheduleOverride);

  @override
  String? get currentUserId => 'owner-user';

  @override
  Future<TenantEntitlementContext?> loadTenantContext(String userId) async =>
      TenantEntitlementContext(
        tenantId: 'tenant-1',
        compatibilityPlanKey: plan,
      );

  @override
  Future<TenantEntitlementSnapshot> loadSnapshot(String tenantId) async =>
      TenantEntitlementSnapshot(
        subscriptionPlanKey: null,
        featureOverrides: [
          if (exportOverride != null)
            EntitlementFeatureValue(
              key: 'reports.export',
              enabled: exportOverride!,
            ),
          if (scheduleOverride != null)
            EntitlementFeatureValue(
              key: 'reports.scheduling',
              enabled: scheduleOverride!,
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
