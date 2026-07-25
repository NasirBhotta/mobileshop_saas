import 'dart:convert';

import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/mobile_services/data/models/mobile_service_models.dart';

abstract interface class MobileServicesLocalDataSource {
  Future<void> saveProviders(List<MobileServiceProviderModel> providers);

  Future<List<MobileServiceProviderModel>> loadProviders(String branchId);

  Future<void> saveChargeRules(List<MobileServiceChargeRuleModel> rules);

  Future<List<MobileServiceChargeRuleModel>> loadChargeRules(String branchId);

  Future<void> saveTransaction(MobileServiceTransactionModel transaction);

  Future<void> applyPendingTransaction(
    MobileServiceTransactionModel transaction,
  );

  Future<List<MobileServiceTransactionModel>> loadTransactions(
    String branchId, {
    required int limit,
  });

  Future<MobileServiceProfitSummary> loadProfitSummary({
    required String branchId,
    required DateTime dayStart,
    required DateTime dayEnd,
  });
}

class MobileServicesLocalStore implements MobileServicesLocalDataSource {
  const MobileServicesLocalStore();

  @override
  Future<void> saveProviders(List<MobileServiceProviderModel> providers) async {
    for (final provider in providers) {
      await LocalDatabase.execute(
        '''
        INSERT OR REPLACE INTO mobile_service_providers(
          id, tenant_id, branch_id, code, name, is_active,
          payload_json, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          provider.id,
          provider.tenantId,
          provider.branchId,
          provider.code.code,
          provider.name,
          provider.isActive ? 1 : 0,
          jsonEncode(provider.toMap()),
          provider.updatedAt.toIso8601String(),
        ],
      );
    }
  }

  @override
  Future<List<MobileServiceProviderModel>> loadProviders(
    String branchId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT payload_json
      FROM mobile_service_providers
      WHERE branch_id = ? AND is_active = 1
      ORDER BY name COLLATE NOCASE
      ''',
      [branchId],
    );
    return rows.map(_providerFromRow).toList();
  }

  @override
  Future<void> saveChargeRules(List<MobileServiceChargeRuleModel> rules) async {
    for (final rule in rules) {
      await LocalDatabase.execute(
        '''
        INSERT OR REPLACE INTO mobile_service_charge_rules(
          id, tenant_id, branch_id, provider_id, operation,
          is_active, payload_json, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          rule.id,
          rule.tenantId,
          rule.branchId,
          rule.providerId,
          rule.operation.code,
          rule.isActive ? 1 : 0,
          jsonEncode(rule.toMap()),
          rule.updatedAt.toIso8601String(),
        ],
      );
    }
  }

  @override
  Future<List<MobileServiceChargeRuleModel>> loadChargeRules(
    String branchId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT payload_json
      FROM mobile_service_charge_rules
      WHERE branch_id = ? AND is_active = 1
      ORDER BY provider_id, operation
      ''',
      [branchId],
    );
    return rows.map(_ruleFromRow).toList();
  }

  @override
  Future<void> saveTransaction(
    MobileServiceTransactionModel transaction,
  ) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO mobile_service_transactions(
        id, tenant_id, branch_id, provider_id, operation,
        status, transaction_at, payload_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        transaction.id,
        transaction.tenantId,
        transaction.branchId,
        transaction.providerId,
        transaction.operation.code,
        transaction.status.code,
        transaction.transactionAt.toIso8601String(),
        jsonEncode(transaction.toMap()),
      ],
    );
  }

  @override
  Future<void> applyPendingTransaction(
    MobileServiceTransactionModel transaction,
  ) {
    if (!transaction.isPendingSync) {
      throw ArgumentError('Only a pending transaction can be applied locally.');
    }

    return LocalDatabase.runInTransaction(() async {
      final existing = await LocalDatabase.select(
        'SELECT id FROM mobile_service_transactions WHERE id = ? LIMIT 1',
        [transaction.id],
      );
      if (existing.isNotEmpty) return;

      final accounts = await LocalDatabase.select(
        '''
        SELECT id, tenant_id, branch_id, account_type, current_balance, is_active
        FROM accounts
        WHERE id IN (?, ?)
        ''',
        [transaction.cashAccountId, transaction.providerAccountId],
      );
      if (accounts.length != 2) {
        throw StateError('Cash and provider accounts must be cached first.');
      }

      final cash = accounts.firstWhere(
        (row) => row['id'] == transaction.cashAccountId,
      );
      final wallet = accounts.firstWhere(
        (row) => row['id'] == transaction.providerAccountId,
      );
      _validateCachedAccount(
        cash,
        transaction: transaction,
        requiredType: 'cash',
      );
      _validateCachedAccount(
        wallet,
        transaction: transaction,
        requiredType: 'mobile_wallet',
      );

      final cashBalance = _number(cash['current_balance']);
      final walletBalance = _number(wallet['current_balance']);
      final isSend = transaction.operation.code == 'send';
      if (isSend && walletBalance < transaction.serviceAmount) {
        throw StateError('Insufficient provider wallet balance.');
      }
      if (!isSend && cashBalance < transaction.customerCashAmount) {
        throw StateError('Insufficient cash balance.');
      }

      await _insertPendingLedgerEntries(transaction);

      await LocalDatabase.execute(
        '''
        UPDATE accounts
        SET current_balance = current_balance + ?, updated_at = ?
        WHERE id = ?
        ''',
        [
          isSend
              ? transaction.customerCashAmount
              : -transaction.customerCashAmount,
          DateTime.now().toIso8601String(),
          transaction.cashAccountId,
        ],
      );
      await LocalDatabase.execute(
        '''
        UPDATE accounts
        SET current_balance = current_balance + ?, updated_at = ?
        WHERE id = ?
        ''',
        [
          isSend ? -transaction.serviceAmount : transaction.serviceAmount,
          DateTime.now().toIso8601String(),
          transaction.providerAccountId,
        ],
      );
      await saveTransaction(transaction);
    });
  }

  @override
  Future<List<MobileServiceTransactionModel>> loadTransactions(
    String branchId, {
    required int limit,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT payload_json
      FROM mobile_service_transactions
      WHERE branch_id = ?
      ORDER BY transaction_at DESC
      LIMIT ?
      ''',
      [branchId, limit],
    );
    return rows.map(_transactionFromRow).toList();
  }

  @override
  Future<MobileServiceProfitSummary> loadProfitSummary({
    required String branchId,
    required DateTime dayStart,
    required DateTime dayEnd,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT payload_json
      FROM mobile_service_transactions
      WHERE branch_id = ?
        AND status IN ('completed', 'pending_sync')
      ''',
      [branchId],
    );
    var todayProfit = 0.0;
    var totalProfit = 0.0;
    var todayCashReceived = 0.0;
    var totalCashReceived = 0.0;
    var todayCashPaid = 0.0;
    var totalCashPaid = 0.0;
    var todayWalletIn = 0.0;
    var totalWalletIn = 0.0;
    var todayWalletOut = 0.0;
    var totalWalletOut = 0.0;
    for (final row in rows) {
      final transaction = _transactionFromRow(row);
      totalProfit += transaction.profitAmount;
      final isCashReceived = transaction.operation.code == 'send';
      if (isCashReceived) {
        totalCashReceived += transaction.customerCashAmount;
        totalWalletOut += transaction.serviceAmount;
      } else {
        totalCashPaid += transaction.customerCashAmount;
        totalWalletIn += transaction.serviceAmount;
      }
      final occurredAt = transaction.transactionAt;
      if (!occurredAt.isBefore(dayStart) && occurredAt.isBefore(dayEnd)) {
        todayProfit += transaction.profitAmount;
        if (isCashReceived) {
          todayCashReceived += transaction.customerCashAmount;
          todayWalletOut += transaction.serviceAmount;
        } else {
          todayCashPaid += transaction.customerCashAmount;
          todayWalletIn += transaction.serviceAmount;
        }
      }
    }
    return MobileServiceProfitSummary(
      todayProfit: todayProfit,
      totalProfit: totalProfit,
      todayCashReceived: todayCashReceived,
      totalCashReceived: totalCashReceived,
      todayCashPaid: todayCashPaid,
      totalCashPaid: totalCashPaid,
      todayWalletIn: todayWalletIn,
      totalWalletIn: totalWalletIn,
      todayWalletOut: todayWalletOut,
      totalWalletOut: totalWalletOut,
    );
  }

  MobileServiceProviderModel _providerFromRow(Map<String, dynamic> row) {
    return MobileServiceProviderModel.fromMap(_decodePayload(row));
  }

  MobileServiceChargeRuleModel _ruleFromRow(Map<String, dynamic> row) {
    return MobileServiceChargeRuleModel.fromMap(_decodePayload(row));
  }

  MobileServiceTransactionModel _transactionFromRow(Map<String, dynamic> row) {
    return MobileServiceTransactionModel.fromMap(_decodePayload(row));
  }

  Map<String, dynamic> _decodePayload(Map<String, dynamic> row) {
    return Map<String, dynamic>.from(
      jsonDecode(row['payload_json'] as String) as Map,
    );
  }

  Future<void> _insertPendingLedgerEntries(
    MobileServiceTransactionModel transaction,
  ) async {
    final isSend = transaction.operation.code == 'send';
    const sql = '''
      INSERT INTO account_transactions(
        id, tenant_id, branch_id, account_id, related_account_id,
        transfer_group_id, transaction_type, direction, amount,
        description, reference_type, reference_id, transaction_at,
        created_by, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''';

    await LocalDatabase.execute(sql, [
      transaction.cashLedgerTransactionId,
      transaction.tenantId,
      transaction.branchId,
      transaction.cashAccountId,
      transaction.providerAccountId,
      transaction.id,
      'mobile_service_cash',
      isSend ? 'in' : 'out',
      transaction.customerCashAmount,
      transaction.description,
      'mobile_service_transaction',
      transaction.id,
      transaction.transactionAt.toIso8601String(),
      transaction.createdBy,
      transaction.createdAt.toIso8601String(),
    ]);
    await LocalDatabase.execute(sql, [
      transaction.providerLedgerTransactionId,
      transaction.tenantId,
      transaction.branchId,
      transaction.providerAccountId,
      transaction.cashAccountId,
      transaction.id,
      'mobile_service_wallet',
      isSend ? 'out' : 'in',
      transaction.serviceAmount,
      transaction.description,
      'mobile_service_transaction',
      transaction.id,
      transaction.transactionAt.toIso8601String(),
      transaction.createdBy,
      transaction.createdAt.toIso8601String(),
    ]);
  }

  void _validateCachedAccount(
    Map<String, dynamic> account, {
    required MobileServiceTransactionModel transaction,
    required String requiredType,
  }) {
    if (account['tenant_id'] != transaction.tenantId ||
        account['branch_id'] != transaction.branchId ||
        account['account_type'] != requiredType ||
        _number(account['is_active']) != 1) {
      throw StateError('Cached account does not match transaction scope.');
    }
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
