import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration =
        File(
          'supabase/migrations/20260719000200_cancel_subscription_at_period_end.sql',
        ).readAsStringSync().toLowerCase();
  });

  test('scheduled cancellation preserves active status and expiry', () {
    expect(migration, contains("action = 'cancel_at_period_end'"));
    expect(migration, contains('set cancel_at_period_end = true'));

    final scheduledBranch = migration.substring(
      migration.indexOf("if action = 'cancel_at_period_end'"),
      migration.indexOf("if action = 'undo_cancel_at_period_end'"),
    );
    expect(scheduledBranch, isNot(contains("status = 'cancelled'")));
    expect(scheduledBranch, isNot(contains('expires_at =')));
  });

  test('scheduled cancellation can be reversed and clears on renewal', () {
    expect(migration, contains("action = 'undo_cancel_at_period_end'"));
    expect(migration, contains('set cancel_at_period_end = false'));
    expect(
      migration,
      contains(
        "when action in ('trial_start', 'trial_extend', 'activate', 'renew', 'cancel') then false",
      ),
    );
  });
}
