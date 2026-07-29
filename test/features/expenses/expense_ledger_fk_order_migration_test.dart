import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expense ledger foreign keys are checked at transaction end', () {
    final sql =
        File(
          'supabase/migrations/'
          '20260729000500_fix_expense_ledger_fk_order.sql',
        ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains(
        'alter constraint expenses_ledger_transaction_id_fkey\n'
        '  deferrable initially deferred',
      ),
    );
    expect(
      sql,
      contains(
        'alter constraint expenses_reversal_ledger_transaction_id_fkey\n'
        '  deferrable initially deferred',
      ),
    );
  });
}
