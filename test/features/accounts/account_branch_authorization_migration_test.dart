import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String evaluator;
  late String accountSecurity;
  late String transfer;
  late String transactionV2;
  late String repository;
  late String provider;

  setUpAll(() {
    evaluator =
        File(
          'supabase/migrations/20260728000050_branch_permission_sql_evaluator.sql',
        ).readAsStringSync();
    accountSecurity =
        File(
          'supabase/migrations/20260728000300_secure_account_branch_mutations.sql',
        ).readAsStringSync();
    transfer =
        File(
          'supabase/migrations/20260728000100_harden_account_transfers.sql',
        ).readAsStringSync();
    transactionV2 =
        File(
          'supabase/migrations/20260728000200_account_source_events_and_reversals.sql',
        ).readAsStringSync();
    repository =
        File(
          'lib/features/accounts/data/repositories/accounts_repository.dart',
        ).readAsStringSync();
    provider =
        File(
          'lib/features/accounts/presentation/providers/accounts_provider.dart',
        ).readAsStringSync();
  });

  test(
    'SQL evaluator mirrors owner, fallback, role, and override precedence',
    () {
      expect(evaluator, contains("if v_actor.role = 'owner' then"));
      expect(
        evaluator,
        contains('from public.user_branch_role_assignments assignment'),
      );
      expect(
        evaluator,
        contains('return public.current_user_has_permission(p_permission_key)'),
      );
      expect(evaluator, contains('and assignment.revoked_at is null'));
      expect(
        evaluator,
        contains('from public.user_branch_permission_overrides override'),
      );
      expect(evaluator, contains('if found then'));
      expect(evaluator, contains('return v_override'));
      expect(
        evaluator,
        contains('from public.role_permissions role_permission'),
      );
    },
  );

  test('SQL evaluator rejects inactive, deleted, and cross-tenant context', () {
    expect(evaluator, contains('v_actor.tenant_id <> p_tenant_id'));
    expect(evaluator, contains('not v_actor.is_active'));
    expect(evaluator, contains('v_actor.deleted_at is not null'));
    expect(evaluator, contains('and b.tenant_id = p_tenant_id'));
  });

  test('all account transaction RPCs require branch create permission', () {
    for (final migration in [accountSecurity, transfer, transactionV2]) {
      expect(migration, contains('public.current_user_has_branch_permission('));
      expect(migration, contains("'account.transaction.create'"));
      expect(migration, contains("errcode = '42501'"));
    }
  });

  test('account RLS separates view, create, and update permissions', () {
    for (final permission in const [
      'account.account.view',
      'account.account.create',
      'account.account.update',
      'account.transaction.view',
    ]) {
      expect(accountSecurity, contains("'$permission'"));
    }
    expect(
      accountSecurity,
      contains('drop policy if exists "tenant users can manage accounts"'),
    );
    expect(
      accountSecurity,
      contains(
        'drop policy if exists "tenant users can manage account transactions"',
      ),
    );
  });

  test('ledger table exposes read policy but no direct write policy', () {
    expect(
      accountSecurity,
      contains('create policy "branch users can read account transactions"'),
    );
    expect(
      accountSecurity,
      isNot(
        contains(
          'create policy "branch users can create account transactions"',
        ),
      ),
    );
    expect(
      accountSecurity,
      isNot(
        contains(
          'create policy "branch users can update account transactions"',
        ),
      ),
    );
    expect(
      accountSecurity,
      isNot(
        contains(
          'create policy "branch users can delete account transactions"',
        ),
      ),
    );
  });

  test('new SQL functions are not executable by public or anon', () {
    expect(evaluator, contains('from public, anon'));
    expect(accountSecurity, contains('from public, anon'));
    expect(evaluator, contains('to authenticated'));
    expect(accountSecurity, contains('to authenticated'));
  });

  test('cached reads and offline writes use the branch-aware client guard', () {
    expect(provider, contains('branchAwarePermissionProvider(permissionKey)'));
    for (final permission in const [
      'account.account.view',
      'account.account.create',
      'account.transaction.view',
      'account.transaction.create',
    ]) {
      expect(repository, contains("_requirePermission('$permission')"));
    }
  });
}
