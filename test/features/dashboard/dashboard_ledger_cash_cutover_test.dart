import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/accounting/ledger_cash_summary.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _tenantId = 'cash-cutover-tenant';
const _branchId = 'cash-cutover-branch';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('cash-cutover-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return databaseDirectory.path;
          }
          return null;
        });
    await LocalDatabase.initialize();
    await LocalDatabase.execute(
      '''
      INSERT INTO accounts(
        id, tenant_id, branch_id, name, account_type, current_balance,
        is_default, is_active
      ) VALUES
        ('drawer', ?, ?, 'Cash in Shop', 'cash', 1300, 1, 1),
        ('wallet', ?, ?, 'Wallet', 'mobile_wallet', 700, 0, 1),
        ('inactive', ?, ?, 'Old Cash', 'cash', 900, 0, 0)
      ''',
      [_tenantId, _branchId, _tenantId, _branchId, _tenantId, _branchId],
    );
  });

  setUp(() async {
    await LocalDatabase.execute('DELETE FROM account_transactions');
    final date = DateTime(2026, 7, 28, 10).toIso8601String();
    await LocalDatabase.execute(
      '''
      INSERT INTO account_transactions(
        id, tenant_id, branch_id, account_id, transaction_type, direction,
        amount, reference_type, transaction_at
      ) VALUES
        ('sale', ?, ?, 'drawer', 'sale', 'in', 500, 'pos_sale_payment', ?),
        ('expense', ?, ?, 'drawer', 'expense', 'out', 120, 'expense', ?),
        ('transfer-out', ?, ?, 'drawer', 'transfer_out', 'out', 200, 'transfer', ?),
        ('transfer-in', ?, ?, 'wallet', 'transfer_in', 'in', 200, 'transfer', ?),
        ('repair', ?, ?, 'drawer', 'other', 'in', 100, 'repair_payment', ?)
      ''',
      [
        _tenantId,
        _branchId,
        date,
        _tenantId,
        _branchId,
        date,
        _tenantId,
        _branchId,
        date,
        _tenantId,
        _branchId,
        date,
        _tenantId,
        _branchId,
        date,
      ],
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('drawer and available money are current account balances', () async {
    final summary = await _summary();
    expect(summary.cashInShop, 1300);
    expect(summary.totalAvailableMoney, 2000);
  });

  test('today flow uses external ledger legs and excludes transfers', () async {
    final summary = await _summary();
    expect(summary.cashIn, 600);
    expect(summary.cashOut, 120);
    expect(summary.netCashFlow, 480);
    expect(summary.inflowBreakdown['repair_payment'], 100);
  });

  test('dashboard, local report, and remote report share ledger source', () {
    final dashboard =
        File(
          'lib/features/dashboard/presentation/providers/dashboard_provider.dart',
        ).readAsStringSync();
    final report =
        File(
          'lib/features/reports/data/local/business_report_local_store.dart',
        ).readAsStringSync();
    final migration =
        File(
          'supabase/migrations/20260728001200_ledger_cash_flow_report.sql',
        ).readAsStringSync().toLowerCase();

    expect(dashboard, contains('LedgerCashSummary.load'));
    expect(report, contains('LedgerCashSummary.load'));
    expect(migration, contains('from public.account_transactions'));
    expect(
      migration,
      contains("transaction_type not in ('transfer_in', 'transfer_out')"),
    );
    expect(migration, isNot(contains('from public.sale_payments')));
    expect(migration, isNot(contains('from public.repair_tickets')));
  });
}

Future<LedgerCashSummary> _summary() {
  final day = DateTime(2026, 7, 28);
  return LedgerCashSummary.load(
    tenantId: _tenantId,
    branchId: _branchId,
    dateFrom: day,
    dateTo: day,
  );
}
