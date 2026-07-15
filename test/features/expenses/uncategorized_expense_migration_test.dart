import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote expenses allow an uncategorized row', () {
    final sql = File(
      'supabase/migrations/20260715002300_allow_uncategorized_expenses.sql',
    ).readAsStringSync();

    expect(sql, contains('alter table public.expenses'));
    expect(sql, contains('alter column category_name drop not null'));
  });
}
