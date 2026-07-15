import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('due recurring expenses catch up and become reportable', () {
    final sql =
        File(
          'supabase/migrations/20260715002600_complete_recurring_expense_lifecycle.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains(
        'drop function if exists public.generate_due_recurring_expenses(uuid, uuid)',
      ),
    );
    expect(sql, contains('while v_due <= current_date'));
    expect(sql, contains("set status = 'confirmed'"));
    expect(sql, contains("v_rule.note, 'confirmed', 'recurring'"));
    expect(sql, contains('set next_due_date = v_due'));
  });
}
