import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';

void main() {
  const ownerOnly = {
    'report.all_branches.view',
    'customer.credit.update',
    'pos.return.override',
  };
  const approvals = {'pos.return.approve', 'pos.discount.approve'};

  test('owner retains all specified access', () async {
    final evaluator = _evaluator({...ownerOnly, ...approvals});
    for (final key in {...ownerOnly, ...approvals}) {
      expect((await evaluator.can(key)).isAllowed, isTrue, reason: key);
    }
  });

  test('manager retains approvals but not owner-only access', () async {
    final evaluator = _evaluator(approvals);
    for (final key in approvals) {
      expect((await evaluator.can(key)).isAllowed, isTrue, reason: key);
    }
    for (final key in ownerOnly) {
      expect((await evaluator.can(key)).isAllowed, isFalse, reason: key);
    }
  });

  test('cashier retains no approval or owner-only access', () async {
    final evaluator = _evaluator(const {});
    for (final key in {...ownerOnly, ...approvals}) {
      expect((await evaluator.can(key)).isAllowed, isFalse, reason: key);
    }
  });

  test('custom role gains only explicitly assigned permission', () async {
    final evaluator = _evaluator(const {'customer.credit.update'});
    expect((await evaluator.can('customer.credit.update')).isAllowed, isTrue);
    expect(
      (await evaluator.can('report.all_branches.view')).isAllowed,
      isFalse,
    );
  });

  test(
    'approver permission can be evaluated for another tenant user',
    () async {
      final evaluator = _evaluator(const {'pos.discount.approve'});
      final result = await evaluator.canFor(
        userId: 'custom-approver',
        tenantId: 'tenant-1',
        permissionKey: 'pos.discount.approve',
      );
      expect(result.isAllowed, isTrue);
    },
  );
}

PermissionEvaluator _evaluator(Set<String> permissions) {
  return PermissionEvaluator(dataSource: _DataSource(permissions));
}

class _DataSource implements PermissionDataSource {
  final Set<String> permissions;

  const _DataSource(this.permissions);

  @override
  String? get currentUserId => 'current-user';

  @override
  Future<String?> loadTenantId(String userId) async => 'tenant-1';

  @override
  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  }) async {
    return [
      PermissionRoleAssignment(
        roleId: 'role-for-$userId',
        isActive: true,
        deletedAt: null,
        revokedAt: null,
        permissionKeys: permissions,
      ),
    ];
  }
}
