import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/branch_permission_shadow_evaluator.dart';

void main() {
  test('owner remains allowed in every branch', () async {
    final result = await _evaluate(
      snapshot: _snapshot(isOwner: true),
      legacyAllowed: false,
    );

    expect(result.branchAllowed, isTrue);
    expect(result.effectiveAllowed, isFalse);
    expect(result.mode, BranchPermissionShadowMode.owner);
  });

  test('unconfigured users retain the legacy decision', () async {
    final result = await _evaluate(
      snapshot: _snapshot(hasBranchConfiguration: false),
      legacyAllowed: true,
    );

    expect(result.branchAllowed, isTrue);
    expect(result.differs, isFalse);
    expect(result.mode, BranchPermissionShadowMode.legacyFallback);
  });

  test(
    'configured user without selected branch role is denied in shadow',
    () async {
      final result = await _evaluate(
        snapshot: _snapshot(
          hasBranchConfiguration: true,
          hasActiveBranchRole: false,
          rolePermissionKeys: {'dashboard.overview.view'},
        ),
        legacyAllowed: true,
      );

      expect(result.branchAllowed, isFalse);
      expect(result.effectiveAllowed, isTrue);
      expect(result.differs, isTrue);
    },
  );

  test('selected branch role grants its permission', () async {
    final result = await _evaluate(
      snapshot: _snapshot(
        hasBranchConfiguration: true,
        hasActiveBranchRole: true,
        rolePermissionKeys: {'dashboard.overview.view'},
      ),
      legacyAllowed: false,
    );

    expect(result.branchAllowed, isTrue);
    expect(result.effectiveAllowed, isFalse);
  });

  test('explicit deny overrides role permission', () async {
    final result = await _evaluate(
      snapshot: _snapshot(
        hasBranchConfiguration: true,
        hasActiveBranchRole: true,
        rolePermissionKeys: {'dashboard.overview.view'},
        permissionOverrides: {'dashboard.overview.view': false},
      ),
      legacyAllowed: true,
    );

    expect(result.branchAllowed, isFalse);
  });

  test('explicit allow adds permission missing from role', () async {
    final result = await _evaluate(
      snapshot: _snapshot(
        hasBranchConfiguration: true,
        hasActiveBranchRole: true,
        permissionOverrides: {'dashboard.overview.view': true},
      ),
      legacyAllowed: false,
    );

    expect(result.branchAllowed, isTrue);
  });
}

Future<BranchPermissionShadowResult> _evaluate({
  required BranchPermissionSnapshot snapshot,
  required bool legacyAllowed,
}) {
  return BranchPermissionShadowEvaluator(
    dataSource: _DataSource(snapshot),
    logger: (_) {},
  ).compare(
    userId: 'staff-user',
    tenantId: 'tenant-1',
    branchId: 'branch-1',
    permissionKey: 'dashboard.overview.view',
    legacyAllowed: legacyAllowed,
  );
}

BranchPermissionSnapshot _snapshot({
  bool isOwner = false,
  bool hasBranchConfiguration = false,
  bool hasActiveBranchRole = false,
  Set<String> rolePermissionKeys = const {},
  Map<String, bool> permissionOverrides = const {},
}) {
  return BranchPermissionSnapshot(
    isOwner: isOwner,
    hasBranchConfiguration: hasBranchConfiguration,
    hasActiveBranchRole: hasActiveBranchRole,
    rolePermissionKeys: rolePermissionKeys,
    permissionOverrides: permissionOverrides,
  );
}

class _DataSource implements BranchPermissionDataSource {
  final BranchPermissionSnapshot snapshot;

  const _DataSource(this.snapshot);

  @override
  Future<BranchPermissionSnapshot> loadSnapshot({
    required String userId,
    required String tenantId,
    required String branchId,
  }) async {
    return snapshot;
  }
}
