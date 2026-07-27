import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/expenses/data/models/expense_models.dart';
import 'package:mobileshop_saas/features/expenses/domain/expense_account_policy.dart';

class ExpenseLocalLedgerCommitter {
  const ExpenseLocalLedgerCommitter._();

  static Future<void> confirm({
    required String expenseId,
    required String accountId,
    required String ledgerTransactionId,
    required String confirmedBy,
    double? actualAmount,
    String? receiptPhotoPath,
    String? localReceiptPath,
  }) async {
    await LocalDatabase.runInTransaction(() async {
      final rows = await LocalDatabase.select(
        'SELECT * FROM expenses WHERE id = ? LIMIT 1',
        [expenseId],
      );
      if (rows.isEmpty) throw StateError('Expense not found.');
      final expense = ExpenseModel.fromMap(rows.single);
      if (expense.status == ExpenseStatus.voided) {
        throw StateError('Voided expense cannot be confirmed.');
      }
      final amount = actualAmount ?? expense.amount;
      if (amount <= 0) {
        throw StateError('Confirmed expense amount must be greater than zero.');
      }

      final accountRows = await LocalDatabase.select(
        'SELECT * FROM accounts WHERE id = ? LIMIT 1',
        [accountId],
      );
      if (accountRows.isEmpty) throw StateError('Paying account not found.');
      final account = AccountModel.fromMap(accountRows.single);
      if (account.tenantId != expense.tenantId ||
          account.branchId != expense.branchId ||
          !ExpenseAccountPolicy.isCompatible(expense.paymentMode, account)) {
        throw StateError('Expense paying account is incompatible.');
      }

      final existingLedger = await LocalDatabase.select(
        'SELECT * FROM account_transactions WHERE id = ? LIMIT 1',
        [ledgerTransactionId],
      );
      if (existingLedger.isNotEmpty) {
        if (expense.ledgerTransactionId != ledgerTransactionId ||
            expense.accountId != accountId ||
            expense.status != ExpenseStatus.confirmed) {
          throw StateError('Expense ledger identity conflicts.');
        }
        return;
      }
      if (account.currentBalance + 0.01 < amount) {
        throw StateError('Paying account balance is insufficient.');
      }

      final now = DateTime.now().toIso8601String();
      await LocalDatabase.execute(
        '''
        UPDATE expenses
        SET amount = ?, account_id = ?, ledger_transaction_id = ?,
            receipt_photo_path = COALESCE(?, receipt_photo_path),
            local_receipt_path = COALESCE(?, local_receipt_path),
            status = 'confirmed', confirmed_by = ?, confirmed_at = ?,
            updated_at = ?
        WHERE id = ?
        ''',
        [
          amount,
          accountId,
          ledgerTransactionId,
          receiptPhotoPath,
          localReceiptPath,
          confirmedBy,
          now,
          now,
          expenseId,
        ],
      );
      await LocalDatabase.execute(
        '''
        INSERT INTO account_transactions(
          id, tenant_id, branch_id, account_id, transaction_type,
          direction, amount, description, reference_type, reference_id,
          source_event_key, transaction_at, created_by, created_at
        )
        VALUES (?, ?, ?, ?, 'expense', 'out', ?, ?, 'expense', ?, ?, ?, ?, ?)
        ''',
        [
          ledgerTransactionId,
          expense.tenantId,
          expense.branchId,
          accountId,
          amount,
          expense.title,
          expenseId,
          'expense:$expenseId:confirm',
          now,
          confirmedBy,
          now,
        ],
      );
      await LocalDatabase.execute(
        '''
        UPDATE accounts
        SET current_balance = current_balance - ?, updated_at = ?
        WHERE id = ?
        ''',
        [amount, now, accountId],
      );
    });
  }

  static Future<void> voidExpense({
    required String expenseId,
    required String voidedBy,
    required String reversalLedgerTransactionId,
  }) async {
    await LocalDatabase.runInTransaction(() async {
      final rows = await LocalDatabase.select(
        'SELECT * FROM expenses WHERE id = ? LIMIT 1',
        [expenseId],
      );
      if (rows.isEmpty) throw StateError('Expense not found.');
      final expense = ExpenseModel.fromMap(rows.single);
      if (expense.status == ExpenseStatus.voided) {
        if (expense.reversalLedgerTransactionId !=
            reversalLedgerTransactionId) {
          throw StateError('Expense reversal identity conflicts.');
        }
        return;
      }
      if (expense.status != ExpenseStatus.confirmed ||
          expense.accountId == null ||
          expense.ledgerTransactionId == null) {
        throw StateError(
          'Only a ledger-linked confirmed expense can be voided.',
        );
      }

      final now = DateTime.now().toIso8601String();
      await LocalDatabase.execute(
        '''
        INSERT INTO account_transactions(
          id, tenant_id, branch_id, account_id, transaction_type,
          direction, amount, description, reference_type, reference_id,
          source_event_key, reversal_of_transaction_id, transaction_at,
          created_by, created_at
        )
        VALUES (?, ?, ?, ?, 'expense', 'in', ?, ?, 'expense_void', ?, ?, ?,
                ?, ?, ?)
        ''',
        [
          reversalLedgerTransactionId,
          expense.tenantId,
          expense.branchId,
          expense.accountId,
          expense.amount,
          'Void: ${expense.title}',
          expenseId,
          'expense:$expenseId:void',
          expense.ledgerTransactionId,
          now,
          voidedBy,
          now,
        ],
      );
      await LocalDatabase.execute(
        '''
        UPDATE accounts
        SET current_balance = current_balance + ?, updated_at = ?
        WHERE id = ?
        ''',
        [expense.amount, now, expense.accountId],
      );
      await LocalDatabase.execute(
        '''
        UPDATE expenses
        SET status = 'void', voided_by = ?, voided_at = ?,
            reversal_ledger_transaction_id = ?, updated_at = ?
        WHERE id = ?
        ''',
        [voidedBy, now, reversalLedgerTransactionId, now, expenseId],
      );
    });
  }
}
