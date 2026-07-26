import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql =
        File(
          'supabase/migrations/20260726000200_branch_scoped_role_foundation.sql',
        ).readAsStringSync();
  });

  test('foundation is additive and leaves current authorization untouched', () {
    expect(sql, contains('create table public.user_branch_role_assignments'));
    expect(
      sql,
      contains('create table public.user_branch_permission_overrides'),
    );
    expect(sql, isNot(contains('alter table public.user_role_assignments')));
    expect(sql, isNot(contains('alter table public.users')));
    expect(sql, isNot(contains('drop table')));
    expect(sql, isNot(contains('public.tenant_subscriptions')));
    expect(sql, isNot(contains('public.tenant_feature_overrides')));
    expect(sql, isNot(contains('feature_entitlement')));
  });

  test('one active role is allowed per user and branch', () {
    expect(
      sql,
      contains(
        'on public.user_branch_role_assignments '
        '(tenant_id, user_id, branch_id)',
      ),
    );
    expect(sql, contains('where revoked_at is null'));
  });

  test('composite foreign keys prevent cross-tenant assignments', () {
    expect(sql, contains('foreign key (user_id, tenant_id)'));
    expect(sql, contains('references public.users(id, tenant_id)'));
    expect(sql, contains('foreign key (branch_id, tenant_id)'));
    expect(sql, contains('references public.branches(id, tenant_id)'));
    expect(sql, contains('foreign key (role_id, tenant_id)'));
    expect(sql, contains('references public.roles(id, tenant_id)'));
  });

  test('only active owner can mutate branch authorization', () {
    expect(sql, contains('public.require_tenant_owner()'));
    expect(sql, contains("u.role = 'owner'"));
    expect(sql, contains('u.is_active'));
    expect(sql, contains('u.deleted_at is null'));
    expect(sql, contains('security definer'));
    expect(
      sql,
      matches(
        RegExp(
          r'revoke all on table public\.user_branch_role_assignments\s+'
          r'from public, anon, authenticated',
        ),
      ),
    );
  });

  test(
    'staff can only read their own rows while owner can read tenant rows',
    () {
      expect(sql, contains('user_id = auth.uid()'));
      expect(sql, contains('tenant_id = public.current_user_tenant_id()'));
      expect(sql, contains("actor.role = 'owner'"));
      expect(
        sql,
        contains(
          'grant select on table public.user_branch_role_assignments '
          'to authenticated',
        ),
      );
    },
  );

  test('owner role cannot be assigned as a branch staff role', () {
    expect(sql, contains("target_user.role <> 'owner'"));
    expect(sql, contains("not (role.is_system and role.code = 'owner')"));
  });

  test('permission override supports allow deny and reset', () {
    expect(sql, contains('p_is_allowed boolean default null'));
    expect(sql, contains('if p_is_allowed is null then'));
    expect(
      sql,
      contains('delete from public.user_branch_permission_overrides'),
    );
    expect(sql, contains('set is_allowed = excluded.is_allowed'));
  });
}
