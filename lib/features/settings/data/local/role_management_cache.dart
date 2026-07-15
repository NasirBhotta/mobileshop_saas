import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/role_management_models.dart';

class RoleManagementCache {
  const RoleManagementCache._();

  static String _key(String tenantId) => 'offline.role_management.$tenantId';

  static Future<void> save(RoleManagementData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(data.tenantId), jsonEncode(data.toMap()));
  }

  static Future<RoleManagementData?> load(String tenantId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(tenantId));
    if (raw == null) return null;
    return RoleManagementData.fromMap(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
      isOffline: true,
    );
  }
}
