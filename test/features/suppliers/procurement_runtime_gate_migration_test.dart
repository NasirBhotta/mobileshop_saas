import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('latest procurement gate does not depend on plan or add-on', () {
    final sql =
        File(
          'supabase/migrations/20260715002100_restore_procurement_runtime_gate.sql',
        ).readAsStringSync();

    expect(
      sql,
      contains('create or replace function public.tenant_procurement_enabled'),
    );
    expect(sql, contains('from public.tenants'));
    expect(sql, isNot(contains("lower(t.plan)")));
    expect(sql, isNot(contains("addon_key = 'supplier_procurement'")));
  });
}
