import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;
  late String localDatabase;

  setUpAll(() {
    sql =
        File(
          'supabase/migrations/20260728001500_repair_hybrid_financial_engine.sql',
        ).readAsStringSync().toLowerCase();
    localDatabase =
        File('lib/core/local/local_database.dart').readAsStringSync();
  });

  test('schema separates parts and immutable financial events', () {
    expect(sql, contains('create table if not exists public.repair_parts'));
    expect(
      sql,
      contains('create table if not exists public.repair_financial_events'),
    );
    expect(sql, contains("source_type in ('inventory','direct_purchase')"));
    expect(sql, contains("event_type in ('completion','reversal')"));
    expect(sql, contains('unique (tenant_id, branch_id, source_event_key)'));
    expect(localDatabase, contains('CREATE TABLE IF NOT EXISTS repair_parts'));
    expect(
      localDatabase,
      contains('CREATE TABLE IF NOT EXISTS repair_financial_events'),
    );
  });

  test('completion consumes inventory and records no money transaction', () {
    final completion = sql.substring(
      sql.indexOf(
        'create or replace function public.complete_repair_ticket_v2',
      ),
      sql.indexOf('create or replace function public.cancel_repair_ticket_v2'),
    );
    expect(completion, contains('quantity = quantity - v_part.quantity'));
    expect(completion, contains("event_type"));
    expect(completion, contains("'completion'"));
    expect(completion, contains("status = 'completed'"));
    expect(completion, isNot(contains('account_transactions')));
  });

  test('cancellation restores inventory and uses a reversal snapshot', () {
    final cancellation = sql.substring(
      sql.indexOf('create or replace function public.cancel_repair_ticket_v2'),
    );
    expect(
      cancellation,
      contains('quantity = public.inventory.quantity + excluded.quantity'),
    );
    expect(cancellation, contains("'reversal'"));
    expect(cancellation, contains('reversal_of_event_id'));
    expect(cancellation, contains("status = 'cancelled'"));
    expect(cancellation, isNot(contains('delete from')));
  });

  test('paid ticket cannot be silently cancelled', () {
    expect(
      sql,
      contains(
        "raise exception 'refund or retain customer credit before cancellation.'",
      ),
    );
  });

  test('new financial tables have read-only client policies', () {
    expect(
      sql,
      contains('alter table public.repair_parts enable row level security'),
    );
    expect(
      sql,
      contains(
        'alter table public.repair_financial_events enable row level security',
      ),
    );
    expect(sql, isNot(contains('for insert to authenticated')));
    expect(sql, isNot(contains('for update to authenticated')));
    expect(sql, isNot(contains('for delete to authenticated')));
  });
}
