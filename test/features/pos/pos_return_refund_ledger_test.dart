import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/pos/data/local/pos_local_refund_committer.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_return_model.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_refund_allocation.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _tenantId = 'refund-tenant';
const _branchId = 'refund-branch';
const _saleId = 'refund-sale';
const _cashId = 'refund-cash';
const _walletId = 'refund-wallet';
const _creditSaleId = 'refund-credit-sale';
const _customerId = 'refund-customer';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('pos-refund-');
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
    await AccountsLocalStore.saveAccount(
      const AccountModel(
        id: _walletId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: 'Wallet',
        type: AccountType.mobileWallet,
      ),
    );
    await LocalDatabase.execute(
      '''
      INSERT INTO sales(
        id, branch_id, user_id, status, subtotal, discount_amount,
        tax_amount, total, synced, created_at
      ) VALUES (?, ?, 'cashier', 'completed', 1000, 0, 0, 1000, 1, ?)
      ''',
      [_saleId, _branchId, DateTime(2026, 7, 28).toIso8601String()],
    );
    await LocalDatabase.execute(
      '''
      INSERT INTO sale_payments(
        id, sale_id, method, amount, account_id, ledger_transaction_id
      ) VALUES
        ('payment-a', ?, 'cash', 400, ?, 'sale-ledger-a'),
        ('payment-b', ?, 'easypaisa', 600, ?, 'sale-ledger-b')
      ''',
      [_saleId, _cashId, _saleId, _walletId],
    );
    await LocalDatabase.execute(
      '''
      INSERT INTO customers(
        id, tenant_id, branch_id, full_name, outstanding_balance
      ) VALUES (?, ?, ?, 'Credit Customer', 500)
      ''',
      [_customerId, _tenantId, _branchId],
    );
    await LocalDatabase.execute(
      '''
      INSERT INTO sales(
        id, branch_id, user_id, customer_id, status, subtotal,
        discount_amount, tax_amount, total, synced, created_at
      ) VALUES (?, ?, 'cashier', ?, 'completed', 500, 0, 0, 500, 1, ?)
      ''',
      [
        _creditSaleId,
        _branchId,
        _customerId,
        DateTime(2026, 7, 28).toIso8601String(),
      ],
    );
    await LocalDatabase.execute(
      '''
      INSERT INTO sale_payments(id, sale_id, method, amount)
      VALUES ('payment-credit', ?, 'credit', 500)
      ''',
      [_creditSaleId],
    );
  });

  setUp(() async {
    await LocalDatabase.execute('DELETE FROM sale_return_refund_legs');
    await LocalDatabase.execute('DELETE FROM sale_return_credit_adjustments');
    await LocalDatabase.execute(
      "DELETE FROM account_transactions WHERE reference_type = 'pos_sale_refund'",
    );
    await LocalDatabase.execute(
      'UPDATE accounts SET current_balance = 1000 WHERE id IN (?, ?)',
      [_cashId, _walletId],
    );
    await LocalDatabase.execute(
      'UPDATE customers SET outstanding_balance = 500 WHERE id = ?',
      [_customerId],
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('mixed payment allocation is stable and respects capacity', () {
    final allocations = PosRefundAllocator.allocate(
      refundAmount: 700,
      payments: const [
        RefundablePaymentLeg(
          paymentId: 'payment-b',
          accountId: _walletId,
          paidAmount: 600,
        ),
        RefundablePaymentLeg(
          paymentId: 'payment-a',
          accountId: _cashId,
          paidAmount: 400,
          alreadyRefunded: 100,
        ),
      ],
    );

    expect(allocations.map((allocation) => allocation.amount).toList(), [
      300,
      400,
    ]);
    expect(allocations.map((allocation) => allocation.paymentId).toList(), [
      'payment-a',
      'payment-b',
    ]);
  });

  test('refund retry changes each original account once', () async {
    final saleReturn = _cashReturn();

    await LocalDatabase.runInTransaction(
      () => PosLocalRefundCommitter.commitWithinTransaction(saleReturn),
    );
    await LocalDatabase.runInTransaction(
      () => PosLocalRefundCommitter.commitWithinTransaction(saleReturn),
    );

    final cash = await AccountsLocalStore.loadAccountById(_cashId);
    final wallet = await AccountsLocalStore.loadAccountById(_walletId);
    final ledger = await LocalDatabase.select(
      "SELECT * FROM account_transactions WHERE reference_type = 'pos_sale_refund'",
    );

    expect(cash?.currentBalance, 600);
    expect(wallet?.currentBalance, 700);
    expect(ledger, hasLength(2));
  });

  test('over-refund rolls back without changing an account', () async {
    final invalid = _cashReturn(
      amount: 401,
      legs: const [
        SaleReturnRefundLegModel(
          id: 'refund-leg-over',
          originalPaymentId: 'payment-a',
          accountId: _cashId,
          amount: 401,
          ledgerTransactionId: 'refund-ledger-over',
        ),
      ],
    );

    await expectLater(
      LocalDatabase.runInTransaction(
        () => PosLocalRefundCommitter.commitWithinTransaction(invalid),
      ),
      throwsStateError,
    );
    expect(
      (await AccountsLocalStore.loadAccountById(_cashId))?.currentBalance,
      1000,
    );
  });

  test('remote migration posts only approved original-payment allocations', () {
    final sql =
        File(
          'supabase/migrations/20260728000600_pos_return_refund_ledger.sql',
        ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains('create table if not exists public.sale_return_refund_legs'),
    );
    expect(
      sql,
      contains('create or replace function public.post_pos_return_refund'),
    );
    expect(sql, contains("'pos.sale.return'"));
    expect(sql, contains("v_return.status <> 'approved'"));
    expect(sql, contains("v_payment.method = 'credit'"));
    expect(sql, contains('refund exceeds the original payment capacity'));
    expect(sql, contains('current_balance = current_balance - v_leg.amount'));
    expect(sql, contains("':payment:' || v_leg.original_payment_id::text"));
  });

  test(
    'credit return retry reduces receivable once without moving cash',
    () async {
      final saleReturn = _creditReturn();
      await LocalDatabase.runInTransaction(
        () => PosLocalRefundCommitter.commitWithinTransaction(saleReturn),
      );
      await LocalDatabase.runInTransaction(
        () => PosLocalRefundCommitter.commitWithinTransaction(saleReturn),
      );

      final customer = await LocalDatabase.select(
        'SELECT outstanding_balance FROM customers WHERE id = ?',
        [_customerId],
      );
      expect((customer.single['outstanding_balance'] as num).toDouble(), 200);
      expect(
        await LocalDatabase.select(
          'SELECT * FROM sale_return_credit_adjustments',
        ),
        hasLength(1),
      );
      expect(
        await LocalDatabase.select(
          "SELECT * FROM account_transactions WHERE source_event_key LIKE 'pos:return:%'",
        ),
        isEmpty,
      );
    },
  );

  test('credit return cannot exceed original credit capacity', () async {
    await expectLater(
      LocalDatabase.runInTransaction(
        () => PosLocalRefundCommitter.commitWithinTransaction(
          _creditReturn(amount: 501),
        ),
      ),
      throwsStateError,
    );
    final customer = await LocalDatabase.select(
      'SELECT outstanding_balance FROM customers WHERE id = ?',
      [_customerId],
    );
    expect((customer.single['outstanding_balance'] as num).toDouble(), 500);
  });

  test('credit return migration changes receivable and never an account', () {
    final sql =
        File(
          'supabase/migrations/20260728001100_pos_credit_return_receivable.sql',
        ).readAsStringSync().toLowerCase();
    expect(sql, contains('function public.post_pos_credit_return'));
    expect(sql, contains('credit return exceeds original credit capacity'));
    expect(sql, contains('outstanding_balance = outstanding_balance -'));
    expect(sql, isNot(contains('update public.accounts')));
  });
}

SaleReturnModel _cashReturn({
  double amount = 700,
  List<SaleReturnRefundLegModel>? legs,
}) {
  return SaleReturnModel(
    id: 'return-1',
    originalSaleId: _saleId,
    branchId: _branchId,
    userId: 'cashier',
    status: SaleReturnStatus.approved,
    refundMethod: RefundMethod.cash,
    refundAmount: amount,
    approvedBy: 'manager',
    createdAt: DateTime(2026, 7, 28, 14),
    items: const [],
    refundLegs:
        legs ??
        const [
          SaleReturnRefundLegModel(
            id: 'refund-leg-a',
            originalPaymentId: 'payment-a',
            accountId: _cashId,
            amount: 400,
            ledgerTransactionId: 'refund-ledger-a',
          ),
          SaleReturnRefundLegModel(
            id: 'refund-leg-b',
            originalPaymentId: 'payment-b',
            accountId: _walletId,
            amount: 300,
            ledgerTransactionId: 'refund-ledger-b',
          ),
        ],
  );
}

SaleReturnModel _creditReturn({double amount = 300}) {
  return SaleReturnModel(
    id: 'credit-return-1',
    originalSaleId: _creditSaleId,
    branchId: _branchId,
    userId: 'cashier',
    status: SaleReturnStatus.approved,
    refundMethod: RefundMethod.credit,
    refundAmount: amount,
    approvedBy: 'owner',
    createdAt: DateTime(2026, 7, 28, 18),
    items: const [],
  );
}
