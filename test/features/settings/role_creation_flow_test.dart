import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'owner role dialog uses name and permissions without a technical code',
    () {
      final source =
          File(
            'lib/features/settings/presentation/widgets/roles_permissions_section.dart',
          ).readAsStringSync();

      expect(source, contains("labelText: 'Role name'"));
      expect(source, contains('permissions: data.permissions'));
      expect(source, contains('permissionKeys: values.permissionKeys'));
      expect(source, isNot(contains("labelText: 'Stable code'")));
      expect(source, isNot(contains('TextEditingController(')));
      expect(source, contains('initialValue: roleName'));
    },
  );

  test('repository creates role and permissions through the additive RPC', () {
    final source =
        File(
          'lib/features/settings/data/repositories/role_management_repository.dart',
        ).readAsStringSync();

    expect(source, contains("_mutate('create_custom_role_with_permissions'"));
    expect(
      source,
      contains("'p_permission_keys': permissionKeys.toList()..sort()"),
    );
  });

  test('migration generates tenant-safe codes and preserves the old RPC', () {
    final source =
        File(
          'supabase/migrations/20260719000700_create_role_with_permissions.sql',
        ).readAsStringSync();

    expect(source, contains('public.require_role_manager_tenant()'));
    expect(source, contains('pg_advisory_xact_lock'));
    expect(source, contains('return public.create_custom_role('));
    expect(source, contains('grant execute on function'));
    expect(source, isNot(contains('drop function public.create_custom_role')));
  });
}
