import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('database invitation flow validates tenant role and Auth email', () {
    final sql =
        File(
          'supabase/migrations/20260719000800_secure_staff_invitations.sql',
        ).readAsStringSync();

    expect(sql, contains('public.require_role_manager_tenant()'));
    expect(sql, contains("not (r.is_system and r.code = 'owner')"));
    expect(sql, contains('auth_email is distinct from invitation.email'));
    expect(sql, contains("auth.role() <> 'service_role'"));
    expect(sql, contains('insert into public.user_role_assignments'));
    expect(sql, contains('role_id <> invitation.role_id'));
    expect(
      sql,
      contains(
        'on conflict (tenant_id, user_id, role_id) where revoked_at is null',
      ),
    );
  });

  test('deployed-database repair reconciles compatibility assignment', () {
    final sql = File(
      'supabase/migrations/20260719000900_reconcile_invited_staff_role.sql',
    ).readAsStringSync();

    expect(sql, contains('role_id <> invitation.role_id'));
    expect(sql, contains('set revoked_at = now()'));
    expect(sql, contains('do nothing'));
  });

  test(
    'Edge Function authenticates caller and rolls back orphan Auth user',
    () {
      final source =
          File('supabase/functions/invite-staff/index.ts').readAsStringSync();

      expect(source, contains('caller.auth.getUser()'));
      expect(source, contains("caller.rpc(\n      'request_staff_invitation'"));
      expect(source, contains('service.auth.admin.inviteUserByEmail'));
    expect(source, contains('service.auth.admin.deleteUser(invitedUserId)'));
    expect(source, contains("from 'jsr:@supabase/supabase-js@2'"));
    expect(source, contains("event: 'staff_invitation_failed'"));
    expect(source, contains("['message', 'error_description', 'details', 'error']"));
    },
  );

  test('Flutter invokes the function without embedding service credentials', () {
    final repository =
        File(
          'lib/features/settings/data/repositories/role_management_repository.dart',
        ).readAsStringSync();
    final ui =
        File(
          'lib/features/settings/presentation/widgets/roles_permissions_section.dart',
        ).readAsStringSync();

    expect(repository, contains(".invoke(\n            'invite-staff'"));
    expect(repository, isNot(contains('service_role')));
    expect(repository, contains('details[\'error\']'));
    expect(ui, contains("label: const Text('Invite User')"));
  });

  test('invited session is forced through password setup route', () {
    final router = File('lib/config/router/app_router.dart').readAsStringSync();
    final screen =
        File(
          'lib/features/auth/presentation/screens/staff_password_setup_screen.dart',
        ).readAsStringSync();

    expect(
      router,
      contains("return isStaffPasswordRoute ? null : '/set-staff-password'"),
    );
    expect(screen, contains('staff_invitation_completed'));
    expect(screen, contains('UserAttributes('));
  });
}
