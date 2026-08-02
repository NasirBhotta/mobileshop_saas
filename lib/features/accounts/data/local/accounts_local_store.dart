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

  static Future<void> setDefaultAccount({
    required String branchId,
    required String accountId,
  }) async {
    await LocalDatabase.runInTransaction(() async {
      await LocalDatabase.execute(
        'UPDATE accounts SET is_default = 0 WHERE branch_id = ?',
        [branchId],
      );
      await LocalDatabase.execute(
        '''
        UPDATE accounts
        SET is_default = 1, updated_at = ?
        WHERE id = ? AND branch_id = ? AND is_active = 1
        ''',
        [DateTime.now().toIso8601String(), accountId, branchId],
      );
    });
  }

  static Future<bool> accountNameExists({
    required String branchId,
    required String name,
    String? excludingAccountId,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT id, name
      FROM accounts
      WHERE branch_id = ?
      ''',
      [branchId],
    );
    final normalized = _normalizeName(name);
    return rows.any(
      (row) =>
          row['id'] != excludingAccountId &&
          _normalizeName(row['name']?.toString() ?? '') == normalized,
    );
  }

  static Future<void> removeAccount(String accountId) async {
    await LocalDatabase.execute('DELETE FROM accounts WHERE id = ?', [
      accountId,
    ]);
  }

  static Future<List<AccountModel>> deactivateSafeDuplicateCashAccounts(
    String branchId,
  ) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM accounts WHERE branch_id = ? AND is_active = 1',
      [branchId],
    );
    final matches =
        rows
            .map(AccountModel.fromMap)
            .where((account) => _normalizeName(account.name) == 'cash in shop')
            .toList();
    if (matches.length < 2) return const [];

    matches.sort((left, right) {
      if (left.isDefault != right.isDefault) return left.isDefault ? -1 : 1;
      final created = (left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      return created != 0 ? created : left.id.compareTo(right.id);
    });

    final deactivated = <AccountModel>[];
    for (final duplicate in matches.skip(1)) {
      if (duplicate.currentBalance.abs() >= 0.01) continue;
      final ledgerRows = await LocalDatabase.select(
        'SELECT 1 FROM account_transactions WHERE account_id = ? LIMIT 1',
        [duplicate.id],
      );
      if (ledgerRows.isNotEmpty) continue;

      final idPrefix =
          duplicate.id.length <= 8
              ? duplicate.id
              : duplicate.id.substring(0, 8);
      final archived = duplicate.copyWith(
        name: '${duplicate.name.trim()} (Archived $idPrefix)',
        isDefault: false,
        isActive: false,
        updatedAt: DateTime.now(),
      );
      await saveAccount(archived);
      deactivated.add(archived);
    }
    return deactivated;
  }

  static Future<void> retainOnlyRemoteActiveAccounts({
    required String branchId,
    required Set<String> activeAccountIds,
  }) async {
    if (activeAccountIds.isEmpty) {
      await LocalDatabase.execute(
        'UPDATE accounts SET is_active = 0 WHERE branch_id = ?',
        [branchId],
      );
      return;
    }
    final placeholders = List.filled(activeAccountIds.length, '?').join(', ');
    await LocalDatabase.execute(
      'UPDATE accounts SET is_active = 0 WHERE branch_id = ? AND id NOT IN ($placeholders)',
      [branchId, ...activeAccountIds],
    );
  }

  static Future<void> saveTransaction(
    AccountTransactionModel transaction,
  ) async {
    await LocalDatabase.execute(
      '''
      INSERT INTO account_transactions(
        id, tenant_id, branch_id, account_id, related_account_id,
        transfer_group_id, transaction_type, direction, amount, description,
        reference_type, reference_id, source_event_key,
        reversal_of_transaction_id, transaction_at, created_by, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        tenant_id = excluded.tenant_id,
        branch_id = excluded.branch_id,
        account_id = excluded.account_id,
        related_account_id = excluded.related_account_id,
        transfer_group_id = excluded.transfer_group_id,
        transaction_type = excluded.transaction_type,
        direction = excluded.direction,
        amount = excluded.amount,
        description = excluded.description,
        reference_type = excluded.reference_type,
        reference_id = excluded.reference_id,
        source_event_key = excluded.source_event_key,
        reversal_of_transaction_id = excluded.reversal_of_transaction_id,
        transaction_at = excluded.transaction_at,
        created_by = excluded.created_by,
        created_at = excluded.created_at
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
        transaction.sourceEventKey,
        transaction.reversalOfTransactionId,
        transaction.transactionAt.toIso8601String(),
        transaction.createdBy,
        transaction.createdAt?.toIso8601String(),
      ],
    );
  }

  static Future<void> applyTransaction(
    AccountTransactionModel transaction,
  ) async {
    await LocalDatabase.runInTransaction(() async {
      if (await _transactionExists(transaction.id)) return;
      final sourceEventKey = transaction.sourceEventKey;
      if (sourceEventKey != null &&
          await _sourceEventExists(
            tenantId: transaction.tenantId,
            branchId: transaction.branchId,
            sourceEventKey: sourceEventKey,
          )) {
        return;
      }
      await _requireAccount(transaction.accountId);
      await _requireValidReversal(transaction);
      await _insertTransaction(transaction);
      await updateAccountBalance(
        accountId: transaction.accountId,
        delta: transaction.signedAmount,
      );
    });
  }

  static Future<void> applyTransfer({
    required AccountTransactionModel outgoing,
    required AccountTransactionModel incoming,
  }) async {
    await LocalDatabase.runInTransaction(() async {
      _requireValidTransferPair(outgoing: outgoing, incoming: incoming);

      final outgoingExists = await _transactionExists(outgoing.id);
      final incomingExists = await _transactionExists(incoming.id);

      if (outgoingExists && incomingExists) return;
      if (outgoingExists != incomingExists) {
        throw StateError(
          'Local account transfer is incomplete and requires reconciliation.',
        );
      }

      final sourceAccount = await _loadAccountRow(outgoing.accountId);
      final destinationAccount = await _loadAccountRow(incoming.accountId);
      _requireTransferAccounts(
        outgoing: outgoing,
        incoming: incoming,
        sourceAccount: sourceAccount,
        destinationAccount: destinationAccount,
      );
      await _insertTransaction(outgoing);
      await _insertTransaction(incoming);
      await updateAccountBalance(
        accountId: outgoing.accountId,
        delta: outgoing.signedAmount,
      );
      await updateAccountBalance(
        accountId: incoming.accountId,
        delta: incoming.signedAmount,
      );
    });
  }

  static Future<bool> _transactionExists(String transactionId) async {
    final rows = await LocalDatabase.select(
      'SELECT 1 FROM account_transactions WHERE id = ? LIMIT 1',
      [transactionId],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _sourceEventExists({
    required String tenantId,
    required String branchId,
    required String sourceEventKey,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT 1
      FROM account_transactions
      WHERE tenant_id = ?
        AND branch_id = ?
        AND source_event_key = ?
      LIMIT 1
      ''',
      [tenantId, branchId, sourceEventKey],
    );
    return rows.isNotEmpty;
  }

  static Future<void> _requireValidReversal(
    AccountTransactionModel transaction,
  ) async {
    final originalId = transaction.reversalOfTransactionId;
    if (originalId == null) return;
    if (originalId == transaction.id) {
      throw ArgumentError('A ledger entry cannot reverse itself.');
    }

    final existingReversal = await LocalDatabase.select(
      '''
      SELECT 1
      FROM account_transactions
      WHERE reversal_of_transaction_id = ?
      LIMIT 1
      ''',
      [originalId],
    );
    if (existingReversal.isNotEmpty) {
      throw StateError('Ledger entry has already been reversed.');
    }

    final rows = await LocalDatabase.select(
      '''
      SELECT tenant_id, branch_id, account_id, direction, amount,
             reversal_of_transaction_id
      FROM account_transactions
      WHERE id = ?
      LIMIT 1
      ''',
      [originalId],
    );
    if (rows.isEmpty) {
      throw StateError('Original ledger entry was not found.');
    }
    final original = rows.single;
    if (original['tenant_id'] != transaction.tenantId ||
        original['branch_id'] != transaction.branchId ||
        original['account_id'] != transaction.accountId) {
      throw StateError('Reversal ledger context does not match.');
    }
    if (original['reversal_of_transaction_id'] != null) {
      throw StateError('A reversal entry cannot be reversed.');
    }
    if (original['direction'] == transaction.direction.code ||
        _number(original['amount']) != transaction.amount) {
      throw StateError(
        'Reversal must use the original amount and opposite direction.',
      );
    }
  }

  static Future<void> _requireAccount(String accountId) async {
    await _loadAccountRow(accountId);
  }

  static Future<Map<String, dynamic>> _loadAccountRow(String accountId) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT id, tenant_id, branch_id, current_balance, is_active
      FROM accounts
      WHERE id = ?
      LIMIT 1
      ''',
      [accountId],
    );
    if (rows.isEmpty) {
      throw StateError('Account not found while applying local ledger entry.');
    }
    return rows.single;
  }

  static void _requireValidTransferPair({
    required AccountTransactionModel outgoing,
    required AccountTransactionModel incoming,
  }) {
    if (outgoing.id == incoming.id) {
      throw ArgumentError('Transfer ledger IDs must be different.');
    }
    if (outgoing.accountId == incoming.accountId) {
      throw ArgumentError('Select two different accounts.');
    }
    if (outgoing.amount <= 0 || incoming.amount <= 0) {
      throw ArgumentError('Transfer amount must be greater than zero.');
    }
    if (outgoing.amount != incoming.amount) {
      throw ArgumentError('Transfer ledger amounts must match.');
    }
    if (outgoing.tenantId != incoming.tenantId ||
        outgoing.branchId != incoming.branchId) {
      throw ArgumentError('Transfer ledger context must match.');
    }
    final groupId = outgoing.transferGroupId;
    if (groupId == null ||
        groupId.isEmpty ||
        incoming.transferGroupId != groupId) {
      throw ArgumentError('Transfer ledger group must match.');
    }
    if (outgoing.type != AccountTransactionType.transferOut ||
        outgoing.direction != AccountTransactionDirection.moneyOut ||
        incoming.type != AccountTransactionType.transferIn ||
        incoming.direction != AccountTransactionDirection.moneyIn) {
      throw ArgumentError('Transfer ledger directions are invalid.');
    }
    if (outgoing.relatedAccountId != incoming.accountId ||
        incoming.relatedAccountId != outgoing.accountId) {
      throw ArgumentError('Transfer ledger account links are invalid.');
    }
  }

  static void _requireTransferAccounts({
    required AccountTransactionModel outgoing,
    required AccountTransactionModel incoming,
    required Map<String, dynamic> sourceAccount,
    required Map<String, dynamic> destinationAccount,
  }) {
    for (final account in [sourceAccount, destinationAccount]) {
      if (account['tenant_id'] != outgoing.tenantId ||
          account['branch_id'] != outgoing.branchId) {
        throw StateError('Transfer account context does not match.');
      }
      if (!_isTrue(account['is_active'])) {
        throw StateError('Transfer account is inactive.');
      }
    }

    if (sourceAccount['id'] != outgoing.accountId ||
        destinationAccount['id'] != incoming.accountId) {
      throw StateError('Transfer accounts do not match their ledger legs.');
    }
    if (_number(sourceAccount['current_balance']) < outgoing.amount) {
      throw StateError('Insufficient source account balance.');
    }
  }

  static Future<void> _insertTransaction(
    AccountTransactionModel transaction,
  ) async {
    await LocalDatabase.execute(
      '''
      INSERT INTO account_transactions(
        id, tenant_id, branch_id, account_id, related_account_id,
        transfer_group_id, transaction_type, direction, amount, description,
        reference_type, reference_id, source_event_key,
        reversal_of_transaction_id, transaction_at, created_by, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        transaction.sourceEventKey,
        transaction.reversalOfTransactionId,
        transaction.transactionAt.toIso8601String(),
        transaction.createdBy,
        transaction.createdAt?.toIso8601String(),
      ],
    );
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

  static Future<List<AccountLedgerReconciliation>> reconcileBranch(
    String branchId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT
        a.id AS account_id,
        a.name AS account_name,
        a.opening_balance AS opening_balance,
        a.current_balance AS stored_balance,
        a.opening_balance + COALESCE(
          SUM(
            CASE
              WHEN t.transaction_type = 'opening_balance' THEN 0
              WHEN t.direction = 'in' THEN t.amount
              WHEN t.direction = 'out' THEN -t.amount
              ELSE 0
            END
          ),
          0
        ) AS expected_balance,
        COUNT(t.id) AS ledger_entry_count
      FROM accounts a
      LEFT JOIN account_transactions t ON t.account_id = a.id
      WHERE a.branch_id = ?
      GROUP BY
        a.id,
        a.name,
        a.opening_balance,
        a.current_balance
      ORDER BY a.name ASC
      ''',
      [branchId],
    );
    return rows.map(AccountLedgerReconciliation.fromMap).toList();
  }

  static bool _isTrue(Object? value) {
    return value == true || value == 1 || value == '1';
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
