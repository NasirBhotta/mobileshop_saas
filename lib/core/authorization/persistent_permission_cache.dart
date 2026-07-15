import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'permission_evaluator.dart';

class PersistentPermissionCache {
  const PersistentPermissionCache._();

  static String _key(String userId, String tenantId) =>
      'offline.permissions.$tenantId.$userId';

  static Future<void> save({
    required String userId,
    required String tenantId,
    required List<PermissionRoleAssignment> assignments,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(userId, tenantId),
      jsonEncode({
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'assignments': [
          for (final assignment in assignments)
            {
              'role_id': assignment.roleId,
              'is_active': assignment.isActive,
              'deleted_at': assignment.deletedAt?.toIso8601String(),
              'revoked_at': assignment.revokedAt?.toIso8601String(),
              'permission_keys': assignment.permissionKeys.toList()..sort(),
            },
        ],
      }),
    );
  }

  static Future<List<PermissionRoleAssignment>?> load({
    required String userId,
    required String tenantId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId, tenantId));
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final rows = map['assignments'] as List?;
    if (rows == null) return null;
    return [
      for (final value in rows)
        if (value is Map)
          PermissionRoleAssignment(
            roleId: value['role_id'] as String,
            isActive: value['is_active'] as bool? ?? false,
            deletedAt: _dateTime(value['deleted_at']),
            revokedAt: _dateTime(value['revoked_at']),
            permissionKeys: Set<String>.from(
              value['permission_keys'] as List? ?? const [],
            ),
          ),
    ];
  }

  static DateTime? _dateTime(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
