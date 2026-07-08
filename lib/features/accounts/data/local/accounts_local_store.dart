import 'package:mobileshop_saas/core/local/local_database.dart';

import '../models/account_models.dart';

class AccountsLocalStore {
  static Future<void> saveAccount(AccountModel account) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO accounts(
        id, tenant_id, branch_id, name, account_type, opening_balance,
        current_balance, is_default, is_active, note, created_by,
        created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        account.id,
        account.tenantId,
        account.branchId,
        account.name,
        account.type.code,
        account.openingBalance,
        account.currentBalance,
        account.isDefault ? 1 : 0,
        account.isActive ? 1 : 0,
        account.note,
        account.createdBy,
        account.createdAt?.toIso8601String(),
        account.updatedAt?.toIso8601String(),
      ],
    );
  }

  static Future<List<AccountModel>> loadAccounts(String branchId) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM accounts
      WHERE branch_id = ?
        AND is_active = 1
      ORDER BY is_default DESC, name ASC
      ''',
      [branchId],
    );

    return rows.map(AccountModel.fromMap).toList();
  }

  static Future<AccountModel?> loadAccountById(String accountId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM accounts WHERE id = ? LIMIT 1',
      [accountId],
    );

    if (rows.isEmpty) return null;
    return AccountModel.fromMap(rows.first);
  }

  static Future<void> saveTransaction(
    AccountTransactionModel transaction,
  ) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO account_transactions(
        id, tenant_id, branch_id, account_id, related_account_id,
        transfer_group_id, transaction_type, direction, amount, description,
        reference_type, reference_id, transaction_at, created_by, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        transaction.id,
        transaction.tenantId,
        transaction.branchId,
        transaction.accountId,
        transaction.relatedAccountId,
        transaction.transferGroupId,
        transaction.type.code,
        transaction.direction.code,
        transaction.amount,
        transaction.description,
        transaction.referenceType,
        transaction.referenceId,
        transaction.transactionAt.toIso8601String(),
        transaction.createdBy,
        transaction.createdAt?.toIso8601String(),
      ],
    );
  }

  static Future<void> applyTransaction(
    AccountTransactionModel transaction,
  ) async {
    await saveTransaction(transaction);
    await updateAccountBalance(
      accountId: transaction.accountId,
      delta: transaction.signedAmount,
    );
  }

  static Future<void> applyTransfer({
    required AccountTransactionModel outgoing,
    required AccountTransactionModel incoming,
  }) async {
    await applyTransaction(outgoing);
    await applyTransaction(incoming);
  }

  static Future<void> updateAccountBalance({
    required String accountId,
    required double delta,
  }) async {
    await LocalDatabase.execute(
      '''
      UPDATE accounts
      SET current_balance = current_balance + ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [delta, DateTime.now().toIso8601String(), accountId],
    );
  }

  static Future<List<AccountTransactionModel>> loadTransactions(
    String branchId, {
    int limit = 80,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM account_transactions
      WHERE branch_id = ?
      ORDER BY transaction_at DESC, created_at DESC
      LIMIT ?
      ''',
      [branchId, limit],
    );

    return rows.map(AccountTransactionModel.fromMap).toList();
  }

  static Future<double> totalBalance(String branchId) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT COALESCE(SUM(current_balance), 0) AS total
      FROM accounts
      WHERE branch_id = ?
        AND is_active = 1
      ''',
      [branchId],
    );

    final value = rows.isEmpty ? null : rows.first['total'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
