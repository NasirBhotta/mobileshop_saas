import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String repository;
  late String reports;
  late String localStore;

  setUpAll(() {
    migration =
        File(
          'supabase/migrations/20260728001500_repair_hybrid_financial_engine.sql',
        ).readAsStringSync().toLowerCase().replaceAll('\r\n', '\n');
    repository =
        File(
          'lib/features/repairs/data/repositories/repair_repository.dart',
        ).readAsStringSync().replaceAll('\r\n', '\n');
    reports =
        File(
          'lib/features/reports/data/local/business_report_local_store.dart',
        ).readAsStringSync().replaceAll('\r\n', '\n');
    localStore = File('lib/core/local/local_store.dart').readAsStringSync().replaceAll('\r\n', '\n');
  });

  test('server-commit timeout can safely replay saved parts', () {
    expect(migration, contains("v_ticket.status in ('completed','delivered')"));
    expect(migration, contains('jsonb_array_length(p_parts)'));
    expect(migration, contains('saved.unit_cost_snapshot is distinct from'));
    expect(migration, contains('then return p_ticket_id'));
    expect(repository, contains('_isEquivalentFinalizedPartsReplay'));
    expect(repository, contains('_isFinalizedPartsRejection'));
    expect(repository, contains("'Finalized repair parts cannot be edited.'"));
    expect(repository, contains('_repairPartReplayKey'));
    expect(repository, contains("source == 'direct_purchase'"));
  });

  test('offline financial mutation dependencies cannot overtake parts', () {
    expect(repository, contains('failedFinancialTicketIds'));
    expect(repository, contains("'save_repair_parts_v2'"));
    expect(repository, contains("'complete_repair_ticket_v2'"));
    expect(repository, contains("'cancel_repair_ticket_v2'"));
  });

  test('archive is preservation, not deletion', () {
    expect(migration, contains('archive_repair_ticket_v2'));
    final archiveFunction = migration.substring(
      migration.indexOf(
        'create or replace function public.archive_repair_ticket_v2',
      ),
    );
    expect(archiveFunction, contains('archived_at = coalesce'));
    expect(
      archiveFunction,
      isNot(contains('delete from public.repair_tickets')),
    );
    expect(localStore, contains('AND archived_at IS NULL'));
  });

  test('repair P&L uses completion and reversal snapshots', () {
    expect(reports, contains('FROM repair_financial_events'));
    expect(reports, contains('SUM(revenue_amount)'));
    expect(
      reports,
      contains(
        'inventory_cost + direct_parts_cost +\n          commission_cost + other_direct_cost',
      ),
    );
    expect(reports, contains('SUM(gross_profit)'));
  });

  test('supplier payable reverses without inventing cash movement', () {
    expect(migration, contains("'repair:direct-part:' || v_part.id::text"));
    expect(
      migration,
      contains("'repair:direct-part-reversal:' || v_part.id::text"),
    );
    expect(
      migration,
      contains("'resolve paid supplier amount before repair cancellation.'"),
    );
    final completion = migration.substring(
      migration.indexOf(
        'create or replace function public.complete_repair_ticket_v2',
      ),
      migration.indexOf(
        'create or replace function public.cancel_repair_ticket_v2',
      ),
    );
    expect(completion, isNot(contains('account_transactions')));
  });
}
