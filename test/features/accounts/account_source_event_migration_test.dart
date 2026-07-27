import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';

void main() {
  late String migration;
  late String localDatabase;

  setUpAll(() {
    migration =
        File(
          'supabase/migrations/20260728000200_account_source_events_and_reversals.sql',
        ).readAsStringSync();
    localDatabase =
        File('lib/core/local/local_database.dart').readAsStringSync();
  });

  test(
    'new fields are nullable and migration performs no guessed backfill',
    () {
      expect(
        migration,
        contains('add column if not exists source_event_key text'),
      );
      expect(
        migration,
        contains('add column if not exists reversal_of_transaction_id uuid'),
      );
      expect(migration, isNot(contains('source_event_key text not null')));
      expect(migration, isNot(contains('update public.account_transactions')));
      expect(migration, isNot(contains('delete from')));
    },
  );

  test('source event and reversal identity are uniquely enforced', () {
    expect(migration, contains('uq_account_transactions_source_event'));
    expect(
      migration,
      contains(
        'on public.account_transactions(tenant_id, branch_id, source_event_key)',
      ),
    );
    expect(migration, contains('where source_event_key is not null'));
    expect(migration, contains('uq_account_transactions_reversal'));
    expect(migration, contains('account_transactions_reversal_fk'));
    expect(migration, contains('account_transactions_not_self_reversal'));
  });

  test('v2 RPC validates and serializes source event retries', () {
    expect(
      migration,
      contains(
        'create or replace function public.record_account_transaction_v2',
      ),
    );
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains('t.source_event_key = p_source_event_key'));
    expect(migration, contains('return v_existing_id'));
  });

  test('v2 RPC validates a full opposite-direction reversal', () {
    for (final rule in const [
      'p_reversal_of_transaction_id = p_transaction_id',
      'v_original.account_id <> p_account_id',
      'v_original.reversal_of_transaction_id is not null',
      'v_original.amount <> p_amount',
      'v_original.direction = p_direction',
      't.reversal_of_transaction_id = p_reversal_of_transaction_id',
    ]) {
      expect(migration, contains(rule), reason: 'Missing reversal rule: $rule');
    }
  });

  test('local schema upgrades existing databases and adds partial indexes', () {
    expect(localDatabase, contains("column: 'source_event_key'"));
    expect(localDatabase, contains("column: 'reversal_of_transaction_id'"));
    expect(localDatabase, contains('uq_account_transactions_source_event'));
    expect(localDatabase, contains('uq_account_transactions_reversal'));
  });

  test('account transaction model preserves new metadata', () {
    final transaction = AccountTransactionModel(
      id: 'tx-1',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      accountId: 'account-1',
      type: AccountTransactionType.adjustment,
      direction: AccountTransactionDirection.moneyOut,
      amount: 25,
      sourceEventKey: 'expense:expense-1:cash',
      reversalOfTransactionId: 'original-1',
      transactionAt: DateTime.utc(2026, 7, 28),
    );

    final restored = AccountTransactionModel.fromMap(transaction.toMap());

    expect(restored.sourceEventKey, 'expense:expense-1:cash');
    expect(restored.reversalOfTransactionId, 'original-1');
  });
}
