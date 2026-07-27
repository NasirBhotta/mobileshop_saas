import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_payment_account_policy.dart';

void main() {
  test('payment account linkage round-trips through the model', () {
    final payment = SalePaymentModel.fromMap({
      'id': 'payment-1',
      'sale_id': 'sale-1',
      'method': 'easypaisa',
      'amount': 1250,
      'account_id': 'account-1',
      'ledger_transaction_id': 'ledger-1',
    });

    expect(payment.accountId, 'account-1');
    expect(payment.ledgerTransactionId, 'ledger-1');
    expect(payment.toMap(), {
      'id': 'payment-1',
      'method': 'easypaisa',
      'amount': 1250.0,
      'account_id': 'account-1',
      'ledger_transaction_id': 'ledger-1',
    });
  });

  test('credit remains valid without an account linkage', () {
    const payment = SalePaymentModel(
      id: 'payment-credit',
      method: PaymentMethod.credit,
      amount: 500,
    );

    expect(payment.toMap().containsKey('account_id'), isFalse);
    expect(payment.toMap().containsKey('ledger_transaction_id'), isFalse);
  });

  test('migration is additive and does not mutate balances', () {
    final sql =
        File(
          'supabase/migrations/20260728000500_pos_payment_account_linkage.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('add column if not exists account_id uuid'));
    expect(
      sql,
      contains('add column if not exists ledger_transaction_id uuid'),
    );
    expect(sql, contains('references public.accounts(id)'));
    expect(sql, contains('references public.account_transactions(id)'));
    expect(
      sql,
      contains('create or replace function public.commit_pos_sale_v2'),
    );
    expect(sql, contains("'pos.sale.create'"));
    expect(sql, contains("transaction_type,\n      direction"));
    expect(sql, contains("'pos:sale:'"));
    expect(sql, contains('if v_ledger_row_count = 1 then'));
    expect(
      sql,
      contains('current_balance = current_balance + v_payment.amount'),
    );
  });

  test('local persistence keeps both linkage fields', () {
    final database =
        File('lib/core/local/local_database.dart').readAsStringSync();
    final store = File('lib/core/local/local_store.dart').readAsStringSync();
    final repository =
        File(
          'lib/features/pos/data/repositories/pos_repository.dart',
        ).readAsStringSync();

    expect(database, contains('ledger_transaction_id TEXT'));
    expect(store, contains('payment.accountId'));
    expect(store, contains('payment.ledgerTransactionId'));
    expect(repository, contains("'account_id': payment['account_id']"));
    expect(
      repository,
      contains("'ledger_transaction_id': payment['ledger_transaction_id']"),
    );
  });

  test('offline sale and ledger use one SQLite transaction', () {
    final committer =
        File(
          'lib/features/pos/data/local/pos_local_ledger_committer.dart',
        ).readAsStringSync();

    expect(committer, contains('LocalDatabase.runInTransaction'));
    expect(committer, contains('await LocalStore.saveSale(sale)'));
    expect(committer, contains('INSERT INTO account_transactions'));
    expect(committer, contains('current_balance = current_balance + ?'));
    expect(committer, contains("final sourceEventKey = 'pos:sale:"));
    expect(committer, contains('ledger identity conflicts'));
  });

  test('payment methods only accept compatible active accounts', () {
    AccountModel account(AccountType type, {bool active = true}) =>
        AccountModel(
          id: type.code,
          tenantId: 'tenant',
          branchId: 'branch',
          name: type.label,
          type: type,
          isActive: active,
        );

    expect(
      PosPaymentAccountPolicy.isCompatible(
        PaymentMethod.cash,
        account(AccountType.cash),
      ),
      isTrue,
    );
    expect(
      PosPaymentAccountPolicy.isCompatible(
        PaymentMethod.easypaisa,
        account(AccountType.mobileWallet),
      ),
      isTrue,
    );
    expect(
      PosPaymentAccountPolicy.isCompatible(
        PaymentMethod.card,
        account(AccountType.bank),
      ),
      isTrue,
    );
    expect(
      PosPaymentAccountPolicy.isCompatible(
        PaymentMethod.cash,
        account(AccountType.mobileWallet),
      ),
      isFalse,
    );
    expect(
      PosPaymentAccountPolicy.isCompatible(
        PaymentMethod.cash,
        account(AccountType.cash, active: false),
      ),
      isFalse,
    );
    expect(
      PosPaymentAccountPolicy.requiresAccount(PaymentMethod.credit),
      isFalse,
    );
  });

  test('only an unambiguous compatible account is suggested', () {
    const defaultCash = AccountModel(
      id: 'cash-default',
      tenantId: 'tenant',
      branchId: 'branch',
      name: 'Cash in Shop',
      type: AccountType.cash,
      isDefault: true,
    );
    const secondCash = AccountModel(
      id: 'cash-2',
      tenantId: 'tenant',
      branchId: 'branch',
      name: 'Counter 2',
      type: AccountType.cash,
    );

    expect(
      PosPaymentAccountPolicy.suggestedAccount(PaymentMethod.cash, [
        defaultCash,
        secondCash,
      ])?.id,
      'cash-default',
    );
    expect(
      PosPaymentAccountPolicy.suggestedAccount(PaymentMethod.cash, [
        secondCash,
        secondCash.copyWith(id: 'cash-3'),
      ]),
      isNull,
    );
  });
}
