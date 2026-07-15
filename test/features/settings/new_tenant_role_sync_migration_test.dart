import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('future compatibility users receive role assignments', () {
    final sql =
        File(
          'supabase/migrations/20260715002200_sync_new_tenant_roles.sql',
        ).readAsStringSync();

    expect(sql, contains('select public.sync_compatibility_system_roles()'));
    expect(
      sql,
      contains('select public.sync_compatibility_role_permissions()'),
    );
    expect(sql, contains('users_ensure_compatibility_role'));
    expect(sql, contains('insert into public.user_role_assignments'));
    expect(sql, contains("assigned_role.code <> new.role"));
  });
}
