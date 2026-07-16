import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql =
        File(
          'supabase/migrations/20260716000300_subscription_lifecycle_states.sql',
        ).readAsStringSync().toLowerCase();
  });

  test('future subscriptions start pending without changing existing rows', () {
    expect(sql, contains("'pending_activation'"));
    expect(sql, contains('existing tenants retain their current statuses'));
    expect(
      sql,
      isNot(
        contains(
          "update public.tenant_subscriptions\nset status = 'pending_activation'",
        ),
      ),
    );
  });

  test('trial end expires instead of activating the subscription', () {
    expect(sql, contains("when action = 'trial_end' then 'trial_expired'"));
    expect(
      sql,
      contains("when action in ('cancel', 'trial_end') then p_effective_at"),
    );
  });

  test('lifecycle RPC validates actions and dates', () {
    expect(sql, contains('the end date must be after the effective date'));
    expect(
      sql,
      contains(
        'a trial can only start for a pending, expired, or cancelled subscription',
      ),
    );
    expect(sql, contains('only an active trial can be ended'));
  });
}
