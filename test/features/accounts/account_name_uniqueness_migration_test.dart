import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration =
        File(
          'supabase/migrations/20260801000100_account_name_uniqueness.sql',
        ).readAsStringSync();
  });

  test('normalizes names and serializes competing writes', () {
    expect(migration, contains("regexp_replace(new.name, '\\s+', ' ', 'g')"));
    expect(migration, contains('lower(new.name)'));
    expect(migration, contains('pg_advisory_xact_lock'));
  });

  test('checks all branch accounts including inactive records', () {
    final triggerFunction = migration.substring(
      migration.indexOf('create or replace function'),
    );
    expect(triggerFunction, contains('account.branch_id = new.branch_id'));
    expect(triggerFunction, isNot(contains('account.is_active')));
    expect(
      triggerFunction,
      contains("raise exception 'ACCOUNT_NAME_EXISTS'"),
    );
  });

  test('legacy cleanup only deactivates empty ledger-free duplicates', () {
    expect(migration, contains('abs(account.current_balance) < 0.01'));
    expect(migration, contains('not exists'));
    expect(migration, contains('transaction.account_id = account.id'));
    expect(migration, contains('is_active = false'));
    expect(migration, contains('(Archived '));
  });
}
