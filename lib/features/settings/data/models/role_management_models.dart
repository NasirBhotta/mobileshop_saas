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

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'description': description,
    'is_system': isSystem,
    'is_active': isActive,
    'permission_keys': permissionKeys.toList()..sort(),
  };

  factory ManagedRole.fromMap(Map<String, dynamic> map) => ManagedRole(
    id: map['id'] as String,
    code: map['code'] as String,
    name: map['name'] as String,
    description: map['description'] as String?,
    isSystem: map['is_system'] as bool? ?? false,
    isActive: map['is_active'] as bool? ?? false,
    permissionKeys: Set<String>.from(
      map['permission_keys'] as List? ?? const [],
    ),
  );
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

  Map<String, dynamic> toMap() => {
    'key': key,
    'module': module,
    'name': name,
    'description': description,
  };

  factory ManagedPermission.fromMap(Map<String, dynamic> map) =>
      ManagedPermission(
        key: map['key'] as String,
        module: map['module'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
      );
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

  Map<String, dynamic> toMap() => {
    'user_id': userId,
    'full_name': fullName,
    'email': email,
    'role_id': roleId,
  };

  factory ManagedUserRole.fromMap(Map<String, dynamic> map) => ManagedUserRole(
    userId: map['user_id'] as String,
    fullName: map['full_name'] as String,
    email: map['email'] as String,
    roleId: map['role_id'] as String?,
  );
}

class RoleManagementData {
  final String tenantId;
  final List<ManagedRole> roles;
  final List<ManagedPermission> permissions;
  final List<ManagedUserRole> users;
  final bool isOffline;
  final DateTime? cachedAt;

  const RoleManagementData({
    required this.tenantId,
    required this.roles,
    required this.permissions,
    required this.users,
    this.isOffline = false,
    this.cachedAt,
  });

  Map<String, dynamic> toMap() => {
    'tenant_id': tenantId,
    'cached_at': (cachedAt ?? DateTime.now().toUtc()).toIso8601String(),
    'roles': roles.map((role) => role.toMap()).toList(),
    'permissions': permissions.map((permission) => permission.toMap()).toList(),
    'users': users.map((user) => user.toMap()).toList(),
  };

  factory RoleManagementData.fromMap(
    Map<String, dynamic> map, {
    bool isOffline = false,
  }) => RoleManagementData(
    tenantId: map['tenant_id'] as String,
    roles: [
      for (final row in map['roles'] as List? ?? const [])
        ManagedRole.fromMap(Map<String, dynamic>.from(row as Map)),
    ],
    permissions: [
      for (final row in map['permissions'] as List? ?? const [])
        ManagedPermission.fromMap(Map<String, dynamic>.from(row as Map)),
    ],
    users: [
      for (final row in map['users'] as List? ?? const [])
        ManagedUserRole.fromMap(Map<String, dynamic>.from(row as Map)),
    ],
    isOffline: isOffline,
    cachedAt: DateTime.tryParse(map['cached_at'] as String? ?? ''),
  );

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

  static List<ManagedRole> assignableStaffRoles(RoleManagementData data) => data
      .roles
      .where((role) => role.isActive && !role.isProtectedOwner)
      .toList(growable: false);
}

abstract final class RoleManagementPermissions {
  static const manage = 'user.role.manage';
}
