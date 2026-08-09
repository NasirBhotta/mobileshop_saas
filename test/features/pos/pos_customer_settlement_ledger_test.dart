import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/pos/data/local/pos_local_settlement_committer.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_dashboard_model.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _tenantId = 'settlement-tenant';
const _branchId = 'settlement-branch';
const _customerId = 'settlement-customer';
const _cashId = 'settlement-cash';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('settlement-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return databaseDirectory.path;
          }
          return null;
        });
    await LocalDatabase.initialize();
    await AccountsLocalStore.saveAccount(
      const AccountModel(
        id: _cashId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: 'Cash in Shop',
      ),
    );
    await LocalDatabase.execute(
      '''
      INSERT INTO customers(
        id, tenant_id, branch_id, full_name, outstanding_balance
      ) VALUES (?, ?, ?, 'Settlement Customer', 1000)
      ''',
      [_customerId, _tenantId, _branchId],
    );
  });

  setUp(() async {
    await LocalDatabase.execute('DELETE FROM customer_settlements');
    await LocalDatabase.execute(
      "DELETE FROM account_transactions WHERE reference_type = 'customer_settlement'",
    );
    await LocalDatabase.execute(
      'UPDATE customers SET outstanding_balance = 1000 WHERE id = ?',
      [_customerId],
    );
    await LocalDatabase.execute(
      'UPDATE accounts SET current_balance = 0 WHERE id = ?',
      [_cashId],
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('settlement retry reduces dues and increases account once', () async {
    final settlement = _settlement();

    await PosLocalSettlementCommitter.commit(
      settlement,
      authoritativeOutstanding: 1000,
    );
    await PosLocalSettlementCommitter.commit(
      settlement,
      authoritativeOutstanding: 1000,
    );

    final customer = await LocalDatabase.select(
      'SELECT outstanding_balance FROM customers WHERE id = ?',
      [_customerId],
    );
    final account = await AccountsLocalStore.loadAccountById(_cashId);
    final ledger = await LocalDatabase.select(
      "SELECT * FROM account_transactions WHERE reference_type = 'customer_settlement'",
    );

    expect((customer.single['outstanding_balance'] as num).toDouble(), 700);
    expect(account?.currentBalance, 300);
    expect(ledger, hasLength(1));
    expect(
      ledger.single['source_event_key'],
      'customer:settlement:settlement-1',
    );
  });

  test('settlement above dues rolls back every local mutation', () async {
    await expectLater(
      PosLocalSettlementCommitter.commit(
        _settlement(amount: 1001),
        authoritativeOutstanding: 1000,
      ),
      throwsStateError,
    );

    expect(
      await LocalDatabase.select('SELECT * FROM customer_settlements'),
      isEmpty,
    );
    expect(
      (await AccountsLocalStore.loadAccountById(_cashId))?.currentBalance,
      0,
    );
  });

  test(
    'consecutive offline settlements use the remaining local dues',
    () async {
      await PosLocalSettlementCommitter.commit(
        _settlement(id: 'settlement-1', ledgerId: 'ledger-1', amount: 300),
        authoritativeOutstanding: 1000,
      );
      await PosLocalSettlementCommitter.commit(
        _settlement(id: 'settlement-2', ledgerId: 'ledger-2', amount: 250),
        authoritativeOutstanding: 700,
      );

      final customer = await LocalDatabase.select(
        'SELECT outstanding_balance FROM customers WHERE id = ?',
        [_customerId],
      );
      final account = await AccountsLocalStore.loadAccountById(_cashId);
      final settlements = await LocalDatabase.select(
        'SELECT id FROM customer_settlements ORDER BY created_at',
      );

      expect((customer.single['outstanding_balance'] as num).toDouble(), 450);
      expect(account?.currentBalance, 550);
      expect(
        settlements.map((row) => row['id']),
        unorderedEquals(['settlement-1', 'settlement-2']),
      );
    },
  );

  test('cross-device conflict stays recorded for manual review', () async {
    final settlement = _settlement();
    await PosLocalSettlementCommitter.commit(
      settlement,
      authoritativeOutstanding: 1000,
    );

    await LocalStore.markCustomerSettlementSyncConflict(
      settlement.id,
      'Remote dues changed before this settlement synced.',
    );

    final stored = await LocalStore.loadCustomerSettlements(_customerId);
    expect(stored.single.syncError, isNotNull);
    expect(
      await LocalDatabase.select(
        'SELECT id FROM customer_settlements WHERE id = ?',
        [settlement.id],
      ),
      isNotEmpty,
    );
  });

  test('remote migration commits receivable and account ledger atomically', () {
    final sql =
        File(
          'supabase/migrations/20260728000700_customer_settlement_account_ledger.sql',
        ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains('create or replace function public.commit_customer_settlement'),
    );
    expect(sql, contains("'customer.credit.settle'"));
    expect(sql, contains('settlement receiving account is incompatible'));
    expect(sql, contains('settlement exceeds current customer dues'));
    expect(sql, contains('outstanding_balance ='));
    expect(sql, contains('current_balance = current_balance + v_amount'));
    expect(sql, contains("'customer:settlement:' || v_id::text"));
    expect(sql, contains('is distinct from v_account_id'));
  });

  test('remote ledger FK allows the atomic RPC insert order', () {
    final sql =
        File(
          'supabase/migrations/20260729000100_fix_customer_settlement_ledger_fk_order.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('alter table public.customer_settlements'));
    expect(
      sql,
      contains(
        'alter constraint customer_settlements_ledger_transaction_id_fkey',
      ),
    );
    expect(sql, contains('deferrable initially deferred'));
  });
}

CustomerSettlementModel _settlement({
  double amount = 300,
  String id = 'settlement-1',
  String ledgerId = 'settlement-ledger-1',
}) {
  return CustomerSettlementModel(
    id: id,
    customerId: _customerId,
    branchId: _branchId,
    userId: 'cashier',
    amount: amount,
    method: 'cash',
    accountId: _cashId,
    ledgerTransactionId: ledgerId,
    createdAt: DateTime(2026, 7, 28, 15),
  );
}
