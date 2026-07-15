import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/settings/data/models/role_management_models.dart';

void main() {
  const owner = ManagedRole(
    id: 'owner-role',
    code: 'owner',
    name: 'Owner',
    description: null,
    isSystem: true,
    isActive: true,
    permissionKeys: {},
  );
  const custom = ManagedRole(
    id: 'custom-role',
    code: 'store_lead',
    name: 'Store Lead',
    description: null,
    isSystem: false,
    isActive: true,
    permissionKeys: {'inventory.product.view'},
  );
  const inactive = ManagedRole(
    id: 'inactive-role',
    code: 'old_role',
    name: 'Old Role',
    description: null,
    isSystem: false,
    isActive: false,
    permissionKeys: {},
  );
  const data = RoleManagementData(
    tenantId: 'tenant-1',
    roles: [owner, custom, inactive],
    permissions: [
      ManagedPermission(
        key: 'inventory.product.view',
        module: 'inventory',
        name: 'View products',
        description: null,
      ),
      ManagedPermission(
        key: 'pos.sale.create',
        module: 'pos',
        name: 'Create sales',
        description: null,
      ),
    ],
    users: [
      ManagedUserRole(
        userId: 'user-1',
        fullName: 'One',
        email: 'one@example.invalid',
        roleId: 'custom-role',
      ),
    ],
  );

  test('role-management access uses the canonical permission', () {
    expect(RoleManagementPermissions.manage, 'user.role.manage');
  });

  test('owner system role remains protected', () {
    expect(RoleManagementRules.canModify(owner), isFalse);
    expect(RoleManagementRules.canModify(custom), isTrue);
  });

  test('assigned active role requires reassignment before deactivation', () {
    expect(RoleManagementRules.requiresReassignment(data, custom), isTrue);
    expect(RoleManagementRules.requiresReassignment(data, owner), isFalse);
  });

  test('only another active role can be a replacement', () {
    final replacements = RoleManagementRules.replacementRoles(data, custom);
    expect(replacements.map((role) => role.id), ['owner-role']);
  });

  test('permissions group by module and assignments count by role', () {
    expect(data.permissionsByModule.keys, containsAll(['inventory', 'pos']));
    expect(data.assignmentCount('custom-role'), 1);
    expect(data.assignmentCount('owner-role'), 0);
  });
}
