import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/network.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'permission_evaluator.dart';
import 'persistent_permission_cache.dart';

class SupabasePermissionDataSource implements PermissionDataSource {
  final SupabaseClient _client;

  SupabasePermissionDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<String?> loadTenantId(String userId) async {
    try {
      final profile = await _client
          .from('users')
          .select('tenant_id')
          .eq('id', userId)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      final tenantId = profile?['tenant_id'] as String?;
      if (tenantId != null) {
        final cached =
            await OfflineStore.loadProfile(userId) ?? <String, dynamic>{};
        cached['id'] ??= userId;
        cached['tenant_id'] = tenantId;
        await OfflineStore.saveProfile(userId, cached);
      }
      return tenantId;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      return (await OfflineStore.loadProfile(userId))?['tenant_id'] as String?;
    }
  }

  @override
  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  }) async {
    try {
      final assignments = await _loadRemoteAssignments(
        userId: userId,
        tenantId: tenantId,
      ).timeout(Network.networkTimeout);
      await PersistentPermissionCache.save(
        userId: userId,
        tenantId: tenantId,
        assignments: assignments,
      );
      return assignments;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      return await PersistentPermissionCache.load(
            userId: userId,
            tenantId: tenantId,
          ) ??
          const [];
    }
  }

  Future<List<PermissionRoleAssignment>> _loadRemoteAssignments({
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

    final roleAssignments = [
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

    return roleAssignments;
  }

  DateTime? _dateTime(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
