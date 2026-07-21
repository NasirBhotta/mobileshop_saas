import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin plan change preserves subscription lifecycle', () {
    final sql =
        File(
          'supabase/migrations/20260719001000_preserve_subscription_on_admin_plan_change.sql',
        ).readAsStringSync();

    expect(sql, contains('for update'));
    expect(sql, contains('set plan_id = p_plan_id'));
    expect(sql, isNot(contains("p_plan_id, 'active'")));
    expect(sql, contains("p_plan_id, 'pending_activation'"));
    expect(sql, contains("'status', current_subscription.status"));
    expect(sql, contains("'expires_at', current_subscription.expires_at"));
  });
}
