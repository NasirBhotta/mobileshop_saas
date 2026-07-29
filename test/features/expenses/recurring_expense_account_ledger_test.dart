import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recurring expenses select and debit a paying account atomically', () {
    final sql =
        File(
          'supabase/migrations/'
          '20260729000600_recurring_expense_account_ledger.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('add column if not exists account_id uuid'));
    expect(sql, contains('recurring expense paying account is required'));
    expect(sql, contains('insert into public.account_transactions'));
    expect(sql, contains("'expense', 'out'"));
    expect(
      sql,
      contains('current_balance = current_balance - v_rule.estimated_amount'),
    );
    expect(sql, contains('ledger_transaction_id'));
    expect(sql, contains('source_event_key'));
  });
}
