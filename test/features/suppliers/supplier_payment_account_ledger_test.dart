import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/suppliers/data/local/procurement_local_store.dart';
import 'package:mobileshop_saas/features/suppliers/data/local/supplier_payment_local_committer.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _tenantId = 'supplier-payment-tenant';
const _branchId = 'supplier-payment-branch';
const _supplierId = 'supplier-payment-supplier';
const _accountId = 'supplier-payment-cash';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('supplier-pay-');
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
        id: _accountId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: 'Cash in Shop',
        currentBalance: 1000,
      ),
    );
    await ProcurementLocalStore.saveSupplier(
      const SupplierModel(
        id: _supplierId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: 'Parts Supplier',
        outstandingBalance: 800,
      ),
    );
  });

  setUp(() async {
    await LocalDatabase.execute('DELETE FROM supplier_payments');
    await LocalDatabase.execute(
      "DELETE FROM account_transactions WHERE reference_type = 'supplier_payment'",
    );
    await LocalDatabase.execute(
      'UPDATE suppliers SET outstanding_balance = 800 WHERE id = ?',
      [_supplierId],
    );
    await LocalDatabase.execute(
      'UPDATE accounts SET current_balance = 1000 WHERE id = ?',
      [_accountId],
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('payment retry changes supplier and account balances once', () async {
    final payment = _payment();
    await SupplierPaymentLocalCommitter.commit(payment);
    await SupplierPaymentLocalCommitter.commit(payment);

    final supplier = await LocalDatabase.select(
      'SELECT outstanding_balance FROM suppliers WHERE id = ?',
      [_supplierId],
    );
    final account = await AccountsLocalStore.loadAccountById(_accountId);
    final ledger = await LocalDatabase.select(
      "SELECT * FROM account_transactions WHERE reference_type = 'supplier_payment'",
    );

    expect((supplier.single['outstanding_balance'] as num).toDouble(), 500);
    expect(account?.currentBalance, 700);
    expect(ledger, hasLength(1));
    expect(ledger.single['source_event_key'], 'supplier:payment:payment-1');
  });

  test('payment above supplier payable rolls back all mutations', () async {
    await expectLater(
      SupplierPaymentLocalCommitter.commit(_payment(amount: 801)),
      throwsStateError,
    );

    expect(
      await LocalDatabase.select('SELECT * FROM supplier_payments'),
      isEmpty,
    );
    expect(
      (await AccountsLocalStore.loadAccountById(_accountId))?.currentBalance,
      1000,
    );
  });

  test('remote migration validates and posts the payment atomically', () {
    final sql =
        File(
          'supabase/migrations/20260728000900_supplier_payment_account_ledger.sql',
        ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains('create or replace function public.record_supplier_payment_v2'),
    );
    expect(sql, contains("'supplier.payment.create'"));
    expect(sql, contains('payment exceeds supplier outstanding balance'));
    expect(sql, contains('paying account balance is insufficient'));
    expect(sql, contains('current_balance = current_balance - p_amount'));
    expect(sql, contains("'supplier:payment:' || p_payment_id::text"));
  });
}

SupplierPaymentModel _payment({double amount = 300}) {
  return SupplierPaymentModel(
    id: 'payment-1',
    tenantId: _tenantId,
    branchId: _branchId,
    supplierId: _supplierId,
    amount: amount,
    method: 'cash',
    accountId: _accountId,
    ledgerTransactionId: 'supplier-ledger-1',
    paidBy: 'owner',
    paidAt: DateTime(2026, 7, 28, 16),
    createdAt: DateTime(2026, 7, 28, 16),
  );
}
