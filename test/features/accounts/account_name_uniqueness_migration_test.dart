import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration =
        File(
          'supabase/migrations/20260821172000_account_active_uniqueness.sql',
        ).readAsStringSync();
  });

  test('normalizes names and serializes competing writes', () {
    expect(migration, contains("regexp_replace(new.name, '\\s+', ' ', 'g')"));
    expect(migration, contains('lower(new.name)'));
    expect(migration, contains('pg_advisory_xact_lock'));
  });

  test('checks branch accounts for active records only', () {
    final triggerFunction = migration.substring(
      migration.indexOf('create or replace function'),
    );
    expect(triggerFunction, contains('account.branch_id = new.branch_id'));
    expect(triggerFunction, contains('account.is_active = true'));
    expect(
      triggerFunction,
      contains("raise exception 'ACCOUNT_NAME_EXISTS'"),
    );
  });
}
