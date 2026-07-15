import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expense void is idempotent and cannot be reversed', () {
    final sql =
        File(
          'supabase/migrations/20260715002400_make_expense_void_idempotent.sql',
        ).readAsStringSync();

    expect(sql, contains('create or replace function public.void_expense'));
    expect(sql, contains("and status <> 'void'"));
    expect(sql, contains("and status = 'void'"));
    expect(sql, contains("old.status = 'void' and new.status <> 'void'"));
  });
}
