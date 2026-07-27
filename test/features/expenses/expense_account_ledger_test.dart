import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/local/accounts_local_store.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/expenses/data/local/expense_local_ledger_committer.dart';
import 'package:mobileshop_saas/features/expenses/data/local/expense_local_store.dart';
import 'package:mobileshop_saas/features/expenses/data/models/expense_models.dart';
import 'package:mobileshop_saas/features/expenses/domain/expense_account_policy.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _tenantId = 'expense-tenant';
const _branchId = 'expense-branch';
const _accountId = 'expense-cash';
const _expenseId = 'expense-1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('expense-ledger-');
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
  });

  setUp(() async {
    await LocalDatabase.execute('DELETE FROM account_transactions');
    await LocalDatabase.execute('DELETE FROM expenses');
    await LocalDatabase.execute(
      'UPDATE accounts SET current_balance = 1000 WHERE id = ?',
      [_accountId],
    );
    await ExpenseLocalStore.saveExpense(_draftExpense());
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('confirm and void retries change account exactly once', () async {
    await _confirm();
    await _confirm();
    expect(
      (await AccountsLocalStore.loadAccountById(_accountId))?.currentBalance,
      700,
    );

    await ExpenseLocalLedgerCommitter.voidExpense(
      expenseId: _expenseId,
      voidedBy: 'owner',
      reversalLedgerTransactionId: 'expense-reversal-1',
    );
    await ExpenseLocalLedgerCommitter.voidExpense(
      expenseId: _expenseId,
      voidedBy: 'owner',
      reversalLedgerTransactionId: 'expense-reversal-1',
    );

    final account = await AccountsLocalStore.loadAccountById(_accountId);
    final ledger = await LocalDatabase.select(
      'SELECT * FROM account_transactions ORDER BY direction',
    );
    final expense = await ExpenseLocalStore.loadExpenseById(_expenseId);

    expect(account?.currentBalance, 1000);
    expect(ledger, hasLength(2));
    expect(
      ledger.firstWhere(
        (row) => row['direction'] == 'in',
      )['reversal_of_transaction_id'],
      'expense-ledger-1',
    );
    expect(expense?.status, ExpenseStatus.voided);
    expect(expense?.reversalLedgerTransactionId, 'expense-reversal-1');
  });

  test('insufficient paying balance rolls back confirmation', () async {
    await expectLater(
      ExpenseLocalLedgerCommitter.confirm(
        expenseId: _expenseId,
        accountId: _accountId,
        ledgerTransactionId: 'expense-ledger-over',
        confirmedBy: 'owner',
        actualAmount: 1001,
      ),
      throwsStateError,
    );

    expect(
      (await ExpenseLocalStore.loadExpenseById(_expenseId))?.status,
      ExpenseStatus.draft,
    );
    expect(
      await LocalDatabase.select('SELECT * FROM account_transactions'),
      isEmpty,
    );
  });

  test('expense payment modes accept only compatible accounts', () {
    const cash = AccountModel(
      id: 'cash',
      tenantId: _tenantId,
      branchId: _branchId,
      name: 'Cash',
      type: AccountType.cash,
    );
    const bank = AccountModel(
      id: 'bank',
      tenantId: _tenantId,
      branchId: _branchId,
      name: 'Bank',
      type: AccountType.bank,
    );

    expect(
      ExpenseAccountPolicy.isCompatible(ExpensePaymentMode.cash, cash),
      isTrue,
    );
    expect(
      ExpenseAccountPolicy.isCompatible(ExpensePaymentMode.bankTransfer, bank),
      isTrue,
    );
    expect(
      ExpenseAccountPolicy.isCompatible(ExpensePaymentMode.bankTransfer, cash),
      isFalse,
    );
  });

  test('remote migration posts and reverses without deleting history', () {
    final sql =
        File(
          'supabase/migrations/20260728000800_expense_account_ledger.sql',
        ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains('create or replace function public.commit_confirmed_expense'),
    );
    expect(
      sql,
      contains('create or replace function public.void_expense_with_reversal'),
    );
    expect(sql, contains("'expense.expense.void'"));
    expect(sql, contains('paying account balance is insufficient'));
    expect(sql, contains('current_balance = current_balance - v_amount'));
    expect(
      sql,
      contains('current_balance = current_balance + v_expense.amount'),
    );
    expect(sql, contains('reversal_of_transaction_id'));
    expect(sql, isNot(contains('delete from public.account_transactions')));
  });
}

Future<void> _confirm() {
  return ExpenseLocalLedgerCommitter.confirm(
    expenseId: _expenseId,
    accountId: _accountId,
    ledgerTransactionId: 'expense-ledger-1',
    confirmedBy: 'owner',
    actualAmount: 300,
  );
}

ExpenseModel _draftExpense() {
  return ExpenseModel(
    id: _expenseId,
    tenantId: _tenantId,
    branchId: _branchId,
    title: 'Shop rent',
    expenseDate: DateTime(2026, 7, 28),
    amount: 300,
    status: ExpenseStatus.draft,
    createdBy: 'owner',
    createdAt: DateTime(2026, 7, 28),
    updatedAt: DateTime(2026, 7, 28),
  );
}
