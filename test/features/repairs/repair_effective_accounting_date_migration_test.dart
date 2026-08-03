import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repair reversals inherit the original accounting date', () {
    final migration =
        File(
          'supabase/migrations/20260802000100_repair_effective_accounting_date.sql',
        ).readAsStringSync();
    final reports =
        File(
          'lib/features/reports/data/local/business_report_local_store.dart',
        ).readAsStringSync();

    expect(migration, contains('add column if not exists effective_at'));
    expect(migration, contains('new.effective_at := v_original_effective_at'));
    expect(migration, contains('new.reversal_of_event_id'));
    expect(reports, contains('substr(effective_at, 1, 10) BETWEEN ? AND ?'));
    expect(
      reports,
      isNot(contains('substr(occurred_at, 1, 10) BETWEEN ? AND ?')),
    );
  });
}
