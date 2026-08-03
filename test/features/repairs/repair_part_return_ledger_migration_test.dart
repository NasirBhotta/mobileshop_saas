import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('part return ledger snapshots prices and is idempotent', () {
    final migration =
        File(
          'supabase/migrations/20260802000200_repair_part_return_ledger.sql',
        ).readAsStringSync();

    expect(
      migration,
      contains('create table if not exists public.repair_part_returns'),
    );
    expect(
      migration,
      contains('add column if not exists settlement_type text'),
    );
    expect(migration, contains("set settlement_type = 'already_recorded'"));
    expect(migration, contains('unit_cost_snapshot'));
    expect(migration, contains('unit_sale_price_snapshot'));
    expect(migration, contains('on conflict (part_id) do nothing'));
    expect(migration, contains("new.event_type = 'reversal'"));
    expect(
      migration,
      contains('after insert on public.repair_financial_events'),
    );
  });
}
