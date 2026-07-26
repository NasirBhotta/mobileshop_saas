import 'package:supabase_flutter/supabase_flutter.dart';

import 'branch_permission_shadow_evaluator.dart';

class SupabaseBranchPermissionDataSource implements BranchPermissionDataSource {
  final SupabaseClient _client;

  SupabaseBranchPermissionDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<BranchPermissionSnapshot> loadSnapshot({
    required String userId,
    required String tenantId,
    required String branchId,
  }) async {
    final profile =
        await _client
            .from('users')
            .select('role')
            .eq('id', userId)
            .eq('tenant_id', tenantId)
            .maybeSingle();
    final assignments = await _client
        .from('user_branch_role_assignments')
        .select('role_id, branch_id, revoked_at')
        .eq('user_id', userId)
        .eq('tenant_id', tenantId);
    final overrideRows = await _client
        .from('user_branch_permission_overrides')
        .select('is_allowed, permissions!inner(key, is_active)')
        .eq('user_id', userId)
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId);
    final selectedAssignment = assignments
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (row) => row?['branch_id'] == branchId && row?['revoked_at'] == null,
          orElse: () => null,
        );
    final roleId = selectedAssignment?['role_id'] as String?;
    final rolePermissions =
        roleId == null
            ? const <String>{}
            : await _loadActiveRolePermissions(
              tenantId: tenantId,
              roleId: roleId,
            );
    final overrides = <String, bool>{};
    for (final row in overrideRows) {
      final permission = row['permissions'] as Map<String, dynamic>;
      if (permission['is_active'] != true) continue;
      overrides[permission['key'] as String] = row['is_allowed'] as bool;
    }

    return BranchPermissionSnapshot(
      isOwner: profile?['role'] == 'owner',
      // Historical rows intentionally count as configuration. Revoking the
      // final branch must not silently restore tenant-wide legacy access.
      hasBranchConfiguration: assignments.isNotEmpty,
      hasActiveBranchRole: roleId != null,
      rolePermissionKeys: rolePermissions,
      permissionOverrides: overrides,
    );
  }

  Future<Set<String>> _loadActiveRolePermissions({
    required String tenantId,
    required String roleId,
  }) async {
    final role =
        await _client
            .from('roles')
            .select('id, is_active, deleted_at')
            .eq('id', roleId)
            .eq('tenant_id', tenantId)
            .maybeSingle();
    if (role == null ||
        role['is_active'] != true ||
        role['deleted_at'] != null) {
      return const {};
    }

    final rows = await _client
        .from('role_permissions')
        .select('permissions!inner(key, is_active)')
        .eq('role_id', roleId);
    return {
      for (final raw in rows)
        if ((raw['permissions'] as Map<String, dynamic>)['is_active'] == true)
          (raw['permissions'] as Map<String, dynamic>)['key'] as String,
    };
  }
}
