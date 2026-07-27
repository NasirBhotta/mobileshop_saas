import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String localStore;

  setUpAll(() {
    migration =
        File(
          'supabase/migrations/20260728000400_account_ledger_reconciliation.sql',
        ).readAsStringSync();
    localStore =
        File(
          'lib/features/accounts/data/local/accounts_local_store.dart',
        ).readAsStringSync();
  });

  test('migration is strictly read-only', () {
    expect(migration, isNot(contains('update public.accounts')));
    expect(migration, isNot(contains('insert into')));
    expect(migration, isNot(contains('delete from')));
    expect(migration, isNot(contains('truncate')));
    expect(migration, isNot(contains('drop table')));
  });

  test('stored balance is reconciled from opening plus signed ledger legs', () {
    for (final source in [migration, localStore]) {
      expect(source, contains("transaction_type = 'opening_balance'"));
      expect(source, contains("direction = 'in'"));
      expect(source, contains("direction = 'out'"));
      expect(source, contains('expected_balance'));
    }
    expect(migration, contains('stored_balance - calculated.expected_balance'));
    expect(migration, contains('<= 0.005'));
  });

  test('integrity summary detects every agreed anomaly class', () {
    for (final key in const [
      'balance_discrepancies',
      'incomplete_transfer_groups',
      'duplicate_source_events',
      'cross_context_transactions',
      'invalid_reversals',
      'is_healthy',
    ]) {
      expect(migration, contains("'$key'"));
    }
  });

  test('transfer health requires exactly one equal IN and OUT leg', () {
    expect(migration, contains('transfer.leg_count <> 2'));
    expect(migration, contains('transfer.out_count <> 1'));
    expect(migration, contains('transfer.in_count <> 1'));
    expect(migration, contains('transfer.out_amount <> transfer.in_amount'));
  });

  test('both diagnostics require branch view permissions', () {
    expect(
      RegExp("'account.account.view'").allMatches(migration),
      hasLength(2),
    );
    expect(
      RegExp("'account.transaction.view'").allMatches(migration),
      hasLength(2),
    );
    expect(RegExp("errcode = '42501'").allMatches(migration), hasLength(2));
  });

  test('diagnostic RPCs are unavailable to public and anon', () {
    expect(RegExp('from public, anon').allMatches(migration), hasLength(2));
    expect(RegExp('to authenticated').allMatches(migration), hasLength(2));
  });
}
