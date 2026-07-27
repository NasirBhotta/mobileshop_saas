import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_payment_account_policy.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_payment_model.dart';

class RepairPaymentLocalCommitter {
  const RepairPaymentLocalCommitter._();

  static Future<void> commit(RepairPaymentModel payment) async {
    await LocalDatabase.runInTransaction(() async {
      final existing = await LocalDatabase.select(
        'SELECT * FROM repair_payments WHERE id = ? LIMIT 1',
        [payment.id],
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['ticket_id'] != payment.ticketId ||
            (row['amount'] as num).toDouble() != payment.amount ||
            row['account_id'] != payment.accountId ||
            row['ledger_transaction_id'] != payment.ledgerTransactionId) {
          throw StateError('Repair payment identity conflicts.');
        }
        return;
      }
      if (payment.amount <= 0) {
        throw StateError('Repair payment must be greater than zero.');
      }

      final ticketRows = await LocalDatabase.select(
        'SELECT * FROM repair_tickets WHERE id = ? LIMIT 1',
        [payment.ticketId],
      );
      if (ticketRows.isEmpty) throw StateError('Repair ticket not found.');
      final ticket = ticketRows.single;
      if (ticket['tenant_id'] != payment.tenantId ||
          ticket['branch_id'] != payment.branchId ||
          ticket['status'] == 'cancelled') {
        throw StateError('Repair ticket context is invalid.');
      }
      final totalCost = (ticket['total_cost'] as num?)?.toDouble();
      if (totalCost == null) {
        throw StateError('Set the final repair amount before receiving money.');
      }
      final paidRows = await LocalDatabase.select(
        'SELECT COALESCE(SUM(amount), 0) AS paid FROM repair_payments WHERE ticket_id = ?',
        [payment.ticketId],
      );
      final paid = (paidRows.single['paid'] as num).toDouble();
      if (paid + payment.amount > totalCost + 0.01) {
        throw StateError('Payment exceeds the repair balance.');
      }

      final accountRows = await LocalDatabase.select(
        'SELECT * FROM accounts WHERE id = ? LIMIT 1',
        [payment.accountId],
      );
      if (accountRows.isEmpty) throw StateError('Receiving account not found.');
      final account = AccountModel.fromMap(accountRows.single);
      final method = PaymentMethodX.fromCode(payment.method);
      if (account.tenantId != payment.tenantId ||
          account.branchId != payment.branchId ||
          !PosPaymentAccountPolicy.isCompatible(method, account)) {
        throw StateError('Repair receiving account is incompatible.');
      }

      await LocalDatabase.execute(
        '''
        INSERT INTO repair_payments(
          id, tenant_id, branch_id, ticket_id, amount, method, account_id,
          ledger_transaction_id, note, received_by, received_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          payment.id,
          payment.tenantId,
          payment.branchId,
          payment.ticketId,
          payment.amount,
          payment.method,
          payment.accountId,
          payment.ledgerTransactionId,
          payment.note,
          payment.receivedBy,
          payment.receivedAt.toIso8601String(),
          payment.createdAt.toIso8601String(),
        ],
      );
      await LocalDatabase.execute(
        '''
        INSERT INTO account_transactions(
          id, tenant_id, branch_id, account_id, transaction_type, direction,
          amount, description, reference_type, reference_id, source_event_key,
          transaction_at, created_by, created_at
        ) VALUES (?, ?, ?, ?, 'other', 'in', ?, 'Repair payment',
                  'repair_payment', ?, ?, ?, ?, ?)
        ''',
        [
          payment.ledgerTransactionId,
          payment.tenantId,
          payment.branchId,
          payment.accountId,
          payment.amount,
          payment.id,
          'repair:payment:${payment.id}',
          payment.receivedAt.toIso8601String(),
          payment.receivedBy,
          payment.createdAt.toIso8601String(),
        ],
      );
      await LocalDatabase.execute(
        'UPDATE accounts SET current_balance = current_balance + ?, updated_at = ? WHERE id = ?',
        [
          payment.amount,
          payment.createdAt.toIso8601String(),
          payment.accountId,
        ],
      );
    });
  }
}
