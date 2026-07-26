import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('permission providers refresh when role data changes', () {
    final provider =
        File(
          'lib/core/authorization/permission_provider.dart',
        ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(provider, contains('permissionRevisionProvider'));
    expect(provider, contains("'roles'"));
    expect(provider, contains("'role_permissions'"));
    expect(provider, contains("'user_role_assignments'"));
    expect(provider, contains('PostgresChangeEvent.all'));
    expect(main, contains('ref.watch(permissionRealtimeRefreshProvider)'));
  });

  test('permission tables are published with full replica identity', () {
    final migration =
        File(
          'supabase/migrations/20260726000100_enable_role_permission_realtime.sql',
        ).readAsStringSync();

    for (final table in const [
      'roles',
      'role_permissions',
      'user_role_assignments',
    ]) {
      expect(migration, contains("'$table'"));
      expect(
        migration,
        contains('alter table public.$table replica identity full'),
      );
    }
    expect(migration, contains('alter publication supabase_realtime'));
  });
}
