import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration =
        File(
          'supabase/migrations/20260728000100_harden_account_transfers.sql',
        ).readAsStringSync();
  });

  test('migration replaces only the transfer RPC and rewrites no data', () {
    expect(
      migration,
      contains('create or replace function public.record_account_transfer'),
    );
    expect(migration, isNot(contains('drop table')));
    expect(migration, isNot(contains('delete from')));
    expect(migration, isNot(contains('truncate')));
    expect(migration, isNot(contains('update public.account_transactions')));
  });

  test('remote transfer validates identity, amount, and account context', () {
    for (final rule in const [
      'p_out_transaction_id = p_in_transaction_id',
      'p_transfer_group_id is null',
      'p_amount is null or p_amount <= 0',
      'p_from_account_id = p_to_account_id',
      'not v_from.is_active or not v_to.is_active',
      'v_from.tenant_id <> p_tenant_id',
      'v_to.tenant_id <> p_tenant_id',
      'v_from.branch_id <> p_branch_id',
      'v_to.branch_id <> p_branch_id',
      'v_from.current_balance < p_amount',
    ]) {
      expect(migration, contains(rule), reason: 'Missing remote rule: $rule');
    }
  });

  test('retry and concurrency protection precede balance mutation', () {
    final retryLock = migration.indexOf('pg_advisory_xact_lock');
    final rowLock = migration.indexOf('for update');
    final insert = migration.indexOf('insert into public.account_transactions');
    final balanceUpdate = migration.indexOf('update public.accounts');

    expect(retryLock, greaterThanOrEqualTo(0));
    expect(rowLock, greaterThan(retryLock));
    expect(insert, greaterThan(rowLock));
    expect(balanceUpdate, greaterThan(insert));
    expect(migration, contains('if v_out_exists and v_in_exists then'));
    expect(migration, contains('if v_out_exists <> v_in_exists then'));
  });

  test('both transfer legs are inserted atomically', () {
    expect(migration, contains("'transfer_out'"));
    expect(migration, contains("'transfer_in'"));
    expect(migration, contains("'out'"));
    expect(migration, contains("'in'"));
    expect(
      RegExp('update public\\.accounts').allMatches(migration),
      hasLength(2),
    );
  });

  test('RPC is unavailable to public and anon roles', () {
    expect(migration, contains('from public, anon'));
    expect(migration, contains('to authenticated'));
  });
}
