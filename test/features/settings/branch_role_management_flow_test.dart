import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/settings/data/models/role_management_models.dart';

void main() {
  test('role data stores a separate role for each user branch', () {
    const data = RoleManagementData(
      tenantId: 'tenant-1',
      roles: [],
      permissions: [],
      users: [],
      branches: [
        ManagedBranch(id: 'branch-a', name: 'Branch A'),
        ManagedBranch(id: 'branch-b', name: 'Branch B'),
      ],
      branchRoles: [
        ManagedUserBranchRole(
          userId: 'staff-1',
          branchId: 'branch-a',
          roleId: 'manager-role',
        ),
        ManagedUserBranchRole(
          userId: 'staff-1',
          branchId: 'branch-b',
          roleId: 'cashier-role',
        ),
      ],
      branchPermissionOverrides: [
        ManagedUserBranchPermissionOverride(
          userId: 'staff-1',
          branchId: 'branch-a',
          permissionKey: 'dashboard.overview.view',
          isAllowed: false,
        ),
      ],
    );

    expect(data.branchRoleId('staff-1', 'branch-a'), 'manager-role');
    expect(data.branchRoleId('staff-1', 'branch-b'), 'cashier-role');
    expect(data.branchRoleId('staff-1', 'branch-c'), isNull);
    expect(data.branchOverrides('staff-1', 'branch-a'), {
      'dashboard.overview.view': false,
    });
  });

  test('offline role snapshot preserves branch assignments', () {
    const original = RoleManagementData(
      tenantId: 'tenant-1',
      roles: [],
      permissions: [],
      users: [],
      branches: [ManagedBranch(id: 'branch-a', name: 'Branch A')],
      branchRoles: [
        ManagedUserBranchRole(
          userId: 'staff-1',
          branchId: 'branch-a',
          roleId: 'manager-role',
        ),
      ],
      branchPermissionOverrides: [
        ManagedUserBranchPermissionOverride(
          userId: 'staff-1',
          branchId: 'branch-a',
          permissionKey: 'dashboard.overview.view',
          isAllowed: true,
        ),
      ],
    );

    final restored = RoleManagementData.fromMap(original.toMap());

    expect(restored.branches.single.name, 'Branch A');
    expect(restored.branchRoleId('staff-1', 'branch-a'), 'manager-role');
    expect(restored.branchOverrides('staff-1', 'branch-a'), {
      'dashboard.overview.view': true,
    });
  });

  test('repository reads branch rows and uses owner RPC for changes', () {
    final source =
        File(
          'lib/features/settings/data/repositories/role_management_repository.dart',
        ).readAsStringSync();

    expect(source, contains(".from('branches')"));
    expect(source, contains(".from('user_branch_role_assignments')"));
    expect(source, contains("_mutate('set_user_branch_role'"));
    expect(source, contains("'p_branch_id': branchId"));
    expect(source, contains("'p_role_id': roleId"));
    expect(source, contains(".from('user_branch_permission_overrides')"));
    expect(
      source,
      contains("_mutate('replace_user_branch_permission_overrides'"),
    );
  });

  test('owner UI exposes branch access without activating enforcement', () {
    final source =
        File(
          'lib/features/settings/presentation/widgets/roles_permissions_section.dart',
        ).readAsStringSync();

    expect(source, contains("tooltip: 'Branch access'"));
    expect(source, contains("child: Text('No access')"));
    expect(source, contains('repository.setUserBranchRole('));
    expect(source, contains("'Customize permissions'"));
    expect(source, contains("'Inherit (Allowed)'"));
    expect(source, contains("'Inherit (Denied)'"));
    expect(source, contains("child: Text('Allow')"));
    expect(source, contains("child: Text('Deny')"));
    expect(source, isNot(contains('branchPermissionShadowProvider')));
  });

  test('override migration validates and replaces changes atomically', () {
    final sql =
        File(
          'supabase/migrations/20260726000300_secure_branch_permission_overrides.sql',
        ).readAsStringSync();

    expect(sql, contains('public.replace_user_branch_permission_overrides'));
    expect(sql, contains('jsonb_typeof(p_overrides)'));
    expect(sql, contains('jsonb_each(p_overrides)'));
    expect(
      sql,
      contains(
        'An active branch role is required before permission overrides.',
      ),
    );
    expect(
      sql,
      contains('delete from public.user_branch_permission_overrides'),
    );
    expect(sql, contains('user_branch_role_override_cleanup'));
    expect(sql, contains('public.require_tenant_owner()'));
  });
}
