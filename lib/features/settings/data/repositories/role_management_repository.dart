import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/network.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/role_management_cache.dart';
import '../models/role_management_models.dart';

class RoleManagementOnlineRequiredException implements Exception {
  const RoleManagementOnlineRequiredException();

  @override
  String toString() =>
      'Security changes ke liye internet connection required hai.';
}

class StaffInvitationException implements Exception {
  final String message;

  const StaffInvitationException(this.message);

  @override
  String toString() => message;
}

class RoleManagementRepository {
  static const _staffInviteTimeout = Duration(seconds: 30);
  final SupabaseClient _client;
  final PermissionEvaluator _permissions;

  RoleManagementRepository({
    SupabaseClient? client,
    required PermissionEvaluator permissions,
  }) : _client = client ?? Supabase.instance.client,
       _permissions = permissions;

  Future<RoleManagementData> load() async {
    await _requireAccess();
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');
    final tenantId = await _tenantId(userId);
    if (tenantId == null) throw Exception('Tenant not found');

    try {
      final data = await _loadRemote(tenantId).timeout(Network.networkTimeout);
      await RoleManagementCache.save(data);
      return data;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      final cached = await RoleManagementCache.load(tenantId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<String?> _tenantId(String userId) async {
    try {
      final profile = await _client
          .from('users')
          .select('tenant_id')
          .eq('id', userId)
          .single()
          .timeout(Network.networkTimeout);
      return profile['tenant_id'] as String?;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      return (await OfflineStore.loadProfile(userId))?['tenant_id'] as String?;
    }
  }

  Future<RoleManagementData> _loadRemote(String tenantId) async {
    final results = await Future.wait([
      _client
          .from('roles')
          .select('id, code, name, description, is_system, is_active')
          .eq('tenant_id', tenantId)
          .order('is_system', ascending: false)
          .order('name'),
      _client
          .from('permissions')
          .select('id, key, module, name, description')
          .eq('is_active', true)
          .order('module')
          .order('name'),
      _client.from('role_permissions').select('role_id, permission_id'),
      _client
          .from('users')
          .select('id, full_name, email')
          .eq('tenant_id', tenantId)
          .order('full_name'),
      _client
          .from('user_role_assignments')
          .select('user_id, role_id')
          .eq('tenant_id', tenantId)
          .isFilter('revoked_at', null),
      _client
          .from('branches')
          .select('id, name')
          .eq('tenant_id', tenantId)
          .order('name'),
      _client
          .from('user_branch_role_assignments')
          .select('user_id, branch_id, role_id')
          .eq('tenant_id', tenantId)
          .isFilter('revoked_at', null),
      _client
          .from('user_branch_permission_overrides')
          .select(
            'user_id, branch_id, is_allowed, '
            'permissions!inner(key, is_active)',
          )
          .eq('tenant_id', tenantId),
    ]);

    final roleRows = results[0];
    final permissionRows = results[1];
    final rolePermissionRows = results[2];
    final userRows = results[3];
    final assignmentRows = results[4];
    final branchRows = results[5];
    final branchRoleRows = results[6];
    final branchOverrideRows = results[7];
    final permissionKeyById = {
      for (final row in permissionRows)
        row['id'] as String: row['key'] as String,
    };
    final keysByRole = <String, Set<String>>{};
    for (final row in rolePermissionRows) {
      final key = permissionKeyById[row['permission_id'] as String];
      if (key != null) {
        keysByRole.putIfAbsent(row['role_id'] as String, () => {}).add(key);
      }
    }
    final roleByUser = <String, String>{};
    for (final row in assignmentRows) {
      roleByUser.putIfAbsent(
        row['user_id'] as String,
        () => row['role_id'] as String,
      );
    }

    return RoleManagementData(
      tenantId: tenantId,
      roles: [
        for (final row in roleRows)
          ManagedRole(
            id: row['id'] as String,
            code: row['code'] as String,
            name: row['name'] as String,
            description: row['description'] as String?,
            isSystem: row['is_system'] as bool? ?? false,
            isActive: row['is_active'] as bool? ?? false,
            permissionKeys: keysByRole[row['id'] as String] ?? const {},
          ),
      ],
      permissions: [
        for (final row in permissionRows)
          ManagedPermission(
            key: row['key'] as String,
            module: row['module'] as String,
            name: row['name'] as String,
            description: row['description'] as String?,
          ),
      ],
      users: [
        for (final row in userRows)
          ManagedUserRole(
            userId: row['id'] as String,
            fullName: row['full_name'] as String? ?? 'Unnamed user',
            email: row['email'] as String? ?? '',
            roleId: roleByUser[row['id'] as String],
          ),
      ],
      branches: [
        for (final row in branchRows)
          ManagedBranch(
            id: row['id'] as String,
            name: row['name'] as String? ?? 'Unnamed branch',
          ),
      ],
      branchRoles: [
        for (final row in branchRoleRows)
          ManagedUserBranchRole(
            userId: row['user_id'] as String,
            branchId: row['branch_id'] as String,
            roleId: row['role_id'] as String,
          ),
      ],
      branchPermissionOverrides: [
        for (final row in branchOverrideRows)
          if ((row['permissions'] as Map<String, dynamic>)['is_active'] == true)
            ManagedUserBranchPermissionOverride(
              userId: row['user_id'] as String,
              branchId: row['branch_id'] as String,
              permissionKey:
                  (row['permissions'] as Map<String, dynamic>)['key'] as String,
              isAllowed: row['is_allowed'] as bool,
            ),
      ],
      cachedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> createRole({
    required String name,
    String? description,
    required Set<String> permissionKeys,
  }) => _mutate('create_custom_role_with_permissions', {
    'p_name': name,
    'p_description': description,
    'p_permission_keys': permissionKeys.toList()..sort(),
  });

  Future<void> renameRole({
    required String roleId,
    required String name,
    String? description,
  }) => _mutate('rename_role', {
    'p_role_id': roleId,
    'p_name': name,
    'p_description': description,
  });

  Future<void> updatePermissions(String roleId, Set<String> permissionKeys) =>
      _mutate('update_role_permissions', {
        'p_role_id': roleId,
        'p_permission_keys': permissionKeys.toList()..sort(),
      });

  Future<void> assignUser(String userId, String roleId) => _mutate(
    'assign_user_to_role',
    {'p_user_id': userId, 'p_role_id': roleId},
  );

  Future<void> setUserBranchRole({
    required String userId,
    required String branchId,
    String? roleId,
  }) => _mutate('set_user_branch_role', {
    'p_user_id': userId,
    'p_branch_id': branchId,
    'p_role_id': roleId,
  });

  Future<void> replaceUserBranchPermissionOverrides({
    required String userId,
    required String branchId,
    required Map<String, bool> overrides,
  }) => _mutate('replace_user_branch_permission_overrides', {
    'p_user_id': userId,
    'p_branch_id': branchId,
    'p_overrides': overrides,
  });

  Future<void> inviteStaff({
    required String fullName,
    required String email,
    required String roleId,
  }) async {
    await _requireAccess();
    try {
      await _client.functions
          .invoke(
            'invite-staff',
            body: {
              'fullName': fullName.trim(),
              'email': email.trim().toLowerCase(),
              'roleId': roleId,
            },
          )
          .timeout(_staffInviteTimeout);
      _permissions.invalidateAll();
    } on FunctionException catch (error) {
      final details = error.details;
      final serverMessage =
          details is Map ? details['error'] ?? details['message'] : null;
      throw StaffInvitationException(
        serverMessage is String && serverMessage.trim().isNotEmpty
            ? serverMessage
            : 'Staff invitation server ne reject kar di (${error.status}).',
      );
    } catch (error) {
      if (OfflineErrorClassifier.isRetryable(error)) {
        throw const RoleManagementOnlineRequiredException();
      }
      rethrow;
    }
  }

  Future<void> moveUsers(String fromRoleId, String toRoleId) => _mutate(
    'move_role_users',
    {'p_from_role_id': fromRoleId, 'p_to_role_id': toRoleId},
  );

  Future<void> setRoleActive(String roleId, bool isActive) => _mutate(
    'set_role_active',
    {'p_role_id': roleId, 'p_is_active': isActive},
  );

  Future<void> _mutate(String function, Map<String, dynamic> parameters) async {
    await _requireAccess();
    try {
      await _client
          .rpc(function, params: parameters)
          .timeout(Network.networkTimeout);
      _permissions.invalidateAll();
    } catch (error) {
      if (OfflineErrorClassifier.isRetryable(error)) {
        throw const RoleManagementOnlineRequiredException();
      }
      rethrow;
    }
  }

  Future<void> _requireAccess() => _permissions.require(
    RoleManagementPermissions.manage,
    message: 'Roles manage karne ki permission required hai.',
  );
}
