import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/pos/data/local/pos_local_ledger_committer.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _tenantId = 'pos-ledger-tenant';
const _branchId = 'pos-ledger-branch';
const _accountId = 'pos-ledger-cash';
const _saleId = 'pos-ledger-sale';
const _paymentId = 'pos-ledger-payment';
const _ledgerId = 'pos-ledger-transaction';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('pos-ledger-');
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
        type: AccountType.cash,
      ),
    );
  });

  setUp(() async {
    await LocalDatabase.execute('DELETE FROM account_transactions');
    await LocalDatabase.execute('DELETE FROM sale_payments');
    await LocalDatabase.execute('DELETE FROM sales');
    await LocalDatabase.execute(
      'UPDATE accounts SET current_balance = 0 WHERE id = ?',
      [_accountId],
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  SaleModel sale({String branchId = _branchId}) => SaleModel(
    id: _saleId,
    branchId: branchId,
    userId: 'cashier',
    subtotal: 750,
    discountAmount: 0,
    taxAmount: 0,
    total: 750,
    payments: const [
      SalePaymentModel(
        id: _paymentId,
        saleId: _saleId,
        method: PaymentMethod.cash,
        amount: 750,
        accountId: _accountId,
        ledgerTransactionId: _ledgerId,
      ),
    ],
    createdAt: DateTime(2026, 7, 28, 12),
  );

  test('sale retry posts one ledger entry and changes balance once', () async {
    await PosLocalLedgerCommitter.commit(sale());
    await PosLocalLedgerCommitter.commit(sale());

    final account = await AccountsLocalStore.loadAccountById(_accountId);
    final ledger = await LocalDatabase.select(
      'SELECT * FROM account_transactions WHERE reference_id = ?',
      [_paymentId],
    );
    final payment = await LocalDatabase.select(
      'SELECT * FROM sale_payments WHERE id = ?',
      [_paymentId],
    );

    expect(account?.currentBalance, 750);
    expect(ledger, hasLength(1));
    expect(
      ledger.single['source_event_key'],
      'pos:sale:$_saleId:payment:$_paymentId',
    );
    expect(payment.single['account_id'], _accountId);
    expect(payment.single['ledger_transaction_id'], _ledgerId);
  });

  test('invalid account context rolls back the complete local sale', () async {
    await expectLater(
      PosLocalLedgerCommitter.commit(sale(branchId: 'another-branch')),
      throwsStateError,
    );

    expect(
      await LocalDatabase.select('SELECT * FROM sales WHERE id = ?', [_saleId]),
      isEmpty,
    );
    expect(
      await LocalDatabase.select(
        'SELECT * FROM account_transactions WHERE id = ?',
        [_ledgerId],
      ),
      isEmpty,
    );
  });
}
