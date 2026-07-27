import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_dashboard_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_payment_account_policy.dart';

class PosLocalSettlementCommitter {
  const PosLocalSettlementCommitter._();

  static Future<void> commit(
    CustomerSettlementModel settlement, {
    required double authoritativeOutstanding,
  }) async {
    await LocalDatabase.runInTransaction(() async {
      final existing = await LocalDatabase.select(
        'SELECT * FROM customer_settlements WHERE id = ? LIMIT 1',
        [settlement.id],
      );
      if (existing.isNotEmpty) {
        _requireIdentical(existing.single, settlement);
        return;
      }

      final accountId = settlement.accountId;
      final ledgerId = settlement.ledgerTransactionId;
      if (accountId == null || ledgerId == null) {
        throw StateError('Settlement account linkage is incomplete.');
      }

      final accounts = await LocalDatabase.select(
        'SELECT * FROM accounts WHERE id = ? LIMIT 1',
        [accountId],
      );
      if (accounts.isEmpty) {
        throw StateError('Settlement receiving account was not found.');
      }
      final account = AccountModel.fromMap(accounts.single);
      final method = PaymentMethodX.fromCode(settlement.method);
      if (account.branchId != settlement.branchId ||
          !PosPaymentAccountPolicy.isCompatible(method, account)) {
        throw StateError('Settlement receiving account is incompatible.');
      }

      final customers = await LocalDatabase.select(
        '''
        SELECT tenant_id, branch_id
        FROM customers
        WHERE id = ?
        LIMIT 1
        ''',
        [settlement.customerId],
      );
      if (customers.isEmpty ||
          customers.single['tenant_id'] != account.tenantId ||
          customers.single['branch_id'] != settlement.branchId) {
        throw StateError('Settlement customer context does not match.');
      }
      if (settlement.amount <= 0 ||
          settlement.amount > authoritativeOutstanding + 0.01) {
        throw StateError('Settlement exceeds current customer dues.');
      }

      await LocalDatabase.execute(
        '''
        INSERT INTO customer_settlements(
          id, customer_id, branch_id, user_id, amount, method, account_id,
          ledger_transaction_id, notes, synced, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
        ''',
        [
          settlement.id,
          settlement.customerId,
          settlement.branchId,
          settlement.userId,
          settlement.amount,
          settlement.method,
          accountId,
          ledgerId,
          settlement.notes,
          settlement.createdAt.toIso8601String(),
        ],
      );
      await LocalDatabase.execute(
        '''
        UPDATE customers
        SET outstanding_balance = MAX(0, ? - ?)
        WHERE id = ?
        ''',
        [authoritativeOutstanding, settlement.amount, settlement.customerId],
      );
      final now = DateTime.now().toIso8601String();
      await LocalDatabase.execute(
        '''
        INSERT INTO account_transactions(
          id, tenant_id, branch_id, account_id, transaction_type,
          direction, amount, description, reference_type, reference_id,
          source_event_key, transaction_at, created_by, created_at
        )
        VALUES (?, ?, ?, ?, 'customer_payment', 'in', ?, ?,
                'customer_settlement', ?, ?, ?, ?, ?)
        ''',
        [
          ledgerId,
          account.tenantId,
          settlement.branchId,
          accountId,
          settlement.amount,
          'Customer dues settlement',
          settlement.id,
          'customer:settlement:${settlement.id}',
          settlement.createdAt.toIso8601String(),
          settlement.userId,
          now,
        ],
      );
      await LocalDatabase.execute(
        '''
        UPDATE accounts
        SET current_balance = current_balance + ?,
            updated_at = ?
        WHERE id = ?
        ''',
        [settlement.amount, now, accountId],
      );
    });
  }

  static void _requireIdentical(
    Map<String, dynamic> existing,
    CustomerSettlementModel settlement,
  ) {
    if (existing['customer_id'] != settlement.customerId ||
        existing['branch_id'] != settlement.branchId ||
        existing['user_id'] != settlement.userId ||
        (existing['amount'] as num).toDouble() != settlement.amount ||
        existing['method'] != settlement.method ||
        existing['account_id'] != settlement.accountId ||
        existing['ledger_transaction_id'] != settlement.ledgerTransactionId) {
      throw StateError('Settlement identity conflicts with existing data.');
    }
  }
}
