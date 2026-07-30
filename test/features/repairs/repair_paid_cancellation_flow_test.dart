import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid cancellation requires an explicit funded refund account', () {
    final screen =
        File(
          'lib/features/repairs/presentation/screens/repairs_list_screen.dart',
        ).readAsStringSync();
    final migration =
        File(
          'supabase/migrations/20260729000200_atomic_paid_repair_cancellation.sql',
        ).readAsStringSync().toLowerCase();

    expect(screen, contains('AppStrings.repairRefundAccount'));
    expect(screen, contains('AppStrings.repairRefundAndCancel'));
    expect(screen, contains('account.currentBalance + 0.01 >= paid'));
    expect(migration, contains('cancel_repair_ticket_v3'));
    expect(
      migration,
      contains('selected account has insufficient refund balance'),
    );
    expect(migration, contains("status = 'cancelled'"));
    expect(migration, contains("state = 'reversed'"));
    expect(migration, contains('current_balance = current_balance - v_paid'));
    expect(migration, contains('-v_completion.gross_profit'));
  });
}
