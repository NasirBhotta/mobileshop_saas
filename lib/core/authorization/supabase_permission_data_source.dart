import 'package:supabase_flutter/supabase_flutter.dart';

import 'permission_evaluator.dart';

class SupabasePermissionDataSource implements PermissionDataSource {
  final SupabaseClient _client;

  SupabasePermissionDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<String?> loadTenantId(String userId) async {
    final profile =
        await _client
            .from('users')
            .select('tenant_id')
            .eq('id', userId)
            .maybeSingle();
    return profile?['tenant_id'] as String?;
  }

  @override
  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  }) async {
    final assignmentRows = await _client
        .from('user_role_assignments')
        .select('role_id, revoked_at')
        .eq('user_id', userId)
        .eq('tenant_id', tenantId);
    if (assignmentRows.isEmpty) return const [];

    final roleIds =
        assignmentRows.map((row) => row['role_id'] as String).toSet().toList();
    final roleRows = await _client
        .from('roles')
        .select('id, is_active, deleted_at')
        .eq('tenant_id', tenantId)
        .inFilter('id', roleIds);
    final roleById = {for (final row in roleRows) row['id'] as String: row};

    final permissionRows = await _client
        .from('role_permissions')
        .select('role_id, permissions!inner(key, is_active)')
        .inFilter('role_id', roleIds);
    final permissionsByRole = <String, Set<String>>{};
    for (final row in permissionRows) {
      final permission = row['permissions'] as Map<String, dynamic>;
      if (permission['is_active'] != true) continue;
      permissionsByRole
          .putIfAbsent(row['role_id'] as String, () => <String>{})
          .add(permission['key'] as String);
    }

    return [
      for (final assignment in assignmentRows)
        if (roleById[assignment['role_id'] as String] case final role?)
          PermissionRoleAssignment(
            roleId: role['id'] as String,
            isActive: role['is_active'] as bool? ?? false,
            deletedAt: _dateTime(role['deleted_at']),
            revokedAt: _dateTime(assignment['revoked_at']),
            permissionKeys: permissionsByRole[role['id'] as String] ?? const {},
          ),
    ];
  }

  DateTime? _dateTime(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
