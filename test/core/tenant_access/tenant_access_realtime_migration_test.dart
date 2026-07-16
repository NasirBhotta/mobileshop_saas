import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tenants table is idempotently enabled for Supabase Realtime', () {
    final sql =
        File(
          'supabase/migrations/20260716000100_enable_tenant_access_realtime.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains("pubname = 'supabase_realtime'"));
    expect(sql, contains("tablename = 'tenants'"));
    expect(
      sql,
      contains('alter publication supabase_realtime add table public.tenants'),
    );
    expect(sql, contains('alter table public.tenants replica identity full'));
  });

  test('current tenant subscription is readable and realtime enabled', () {
    final sql =
        File(
          'supabase/migrations/20260716000200_enable_subscription_runtime_access.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('tenant users read own current subscription'));
    expect(sql, contains('tenant_id = public.current_user_tenant_id()'));
    expect(sql, contains("tablename = 'tenant_subscriptions'"));
    expect(
      sql,
      contains(
        'alter publication supabase_realtime\n      add table public.tenant_subscriptions',
      ),
    );
  });
}
