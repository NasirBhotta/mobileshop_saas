class ManagedRole {
  final String id;
  final String code;
  final String name;
  final String? description;
  final bool isSystem;
  final bool isActive;
  final Set<String> permissionKeys;

  const ManagedRole({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.isSystem,
    required this.isActive,
    required this.permissionKeys,
  });

  bool get isProtectedOwner => isSystem && code == 'owner';
}

class ManagedPermission {
  final String key;
  final String module;
  final String name;
  final String? description;

  const ManagedPermission({
    required this.key,
    required this.module,
    required this.name,
    required this.description,
  });
}

class ManagedUserRole {
  final String userId;
  final String fullName;
  final String email;
  final String? roleId;

  const ManagedUserRole({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.roleId,
  });
}

class RoleManagementData {
  final String tenantId;
  final List<ManagedRole> roles;
  final List<ManagedPermission> permissions;
  final List<ManagedUserRole> users;

  const RoleManagementData({
    required this.tenantId,
    required this.roles,
    required this.permissions,
    required this.users,
  });

  Map<String, List<ManagedPermission>> get permissionsByModule {
    final grouped = <String, List<ManagedPermission>>{};
    for (final permission in permissions) {
      grouped.putIfAbsent(permission.module, () => []).add(permission);
    }
    for (final values in grouped.values) {
      values.sort((a, b) => a.name.compareTo(b.name));
    }
    return grouped;
  }

  int assignmentCount(String roleId) =>
      users.where((user) => user.roleId == roleId).length;
}

abstract final class RoleManagementRules {
  static bool canModify(ManagedRole role) => !role.isProtectedOwner;

  static bool requiresReassignment(RoleManagementData data, ManagedRole role) =>
      role.isActive && data.assignmentCount(role.id) > 0;

  static List<ManagedRole> replacementRoles(
    RoleManagementData data,
    ManagedRole role,
  ) => data.roles
      .where((candidate) => candidate.isActive && candidate.id != role.id)
      .toList(growable: false);
}

abstract final class RoleManagementPermissions {
  static const manage = 'user.role.manage';
}
