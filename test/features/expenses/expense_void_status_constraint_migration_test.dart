import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('latest expense constraint accepts canonical void status', () {
    final sql = File(
      'supabase/migrations/20260715002500_fix_expense_void_status_constraint.sql',
    ).readAsStringSync();

    expect(sql, contains('drop constraint if exists expenses_status_check'));
    expect(sql, contains("set status = 'void'"));
    expect(sql, contains("where status = 'cancelled'"));
    expect(sql, contains("check (status in ('draft', 'confirmed', 'void'))"));
  });
}
