import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tenants table is idempotently enabled for Supabase Realtime', () {
    final sql = File(
      'supabase/migrations/20260716000100_enable_tenant_access_realtime.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains("pubname = 'supabase_realtime'"));
    expect(sql, contains("tablename = 'tenants'"));
    expect(sql, contains('alter publication supabase_realtime add table public.tenants'));
    expect(sql, contains('alter table public.tenants replica identity full'));
  });
}
