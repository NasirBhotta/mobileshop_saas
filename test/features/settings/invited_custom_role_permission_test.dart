import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';

void main() {
  const invitedUserId = 'invited-manager-user';
  const tenantId = 'tenant-1';
  const customRoleId = 'custom-manager-role';
  const selectedPermission = 'inventory.product.view';
  const unselectedPermission = 'inventory.product.create';

  test('invitation completion keeps exactly the selected custom role active', () {
    final sql =
        File(
          'supabase/migrations/20260719000900_reconcile_invited_staff_role.sql',
        ).readAsStringSync();

    expect(sql, contains('role_id <> invitation.role_id'));
    expect(sql, contains('set revoked_at = now()'));
    expect(
      sql,
      contains(
        'insert into public.user_role_assignments '
        '(tenant_id, user_id, role_id)',
      ),
    );
    expect(
      sql,
      contains('values (invitation.tenant_id, p_user_id, invitation.role_id)'),
    );
  });

  test('invited custom-role user gets selected permission only', () async {
    final evaluator = PermissionEvaluator(
      dataSource: const _InvitedUserPermissionDataSource(
        userId: invitedUserId,
        tenantId: tenantId,
        roleId: customRoleId,
        permissionKeys: {selectedPermission},
      ),
    );

    final allowed = await evaluator.can(selectedPermission);
    final denied = await evaluator.can(unselectedPermission);

    expect(allowed.isAllowed, isTrue);
    expect(allowed.userId, invitedUserId);
    expect(allowed.tenantId, tenantId);
    expect(denied.isAllowed, isFalse);
    expect(denied.denialReason, PermissionDenialReason.permissionMissing);
  });
}

class _InvitedUserPermissionDataSource implements PermissionDataSource {
  final String userId;
  final String tenantId;
  final String roleId;
  final Set<String> permissionKeys;

  const _InvitedUserPermissionDataSource({
    required this.userId,
    required this.tenantId,
    required this.roleId,
    required this.permissionKeys,
  });

  @override
  String? get currentUserId => userId;

  @override
  Future<String?> loadTenantId(String userId) async {
    return userId == this.userId ? tenantId : null;
  }

  @override
  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  }) async {
    if (userId != this.userId || tenantId != this.tenantId) {
      return const [];
    }

    return [
      PermissionRoleAssignment(
        roleId: roleId,
        isActive: true,
        deletedAt: null,
        revokedAt: null,
        permissionKeys: permissionKeys,
      ),
    ];
  }
}
