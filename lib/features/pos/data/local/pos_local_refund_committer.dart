import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_return_model.dart';

class PosLocalRefundCommitter {
  const PosLocalRefundCommitter._();

  static Future<void> commitWithinTransaction(
    SaleReturnModel saleReturn,
  ) async {
    if (saleReturn.status != SaleReturnStatus.approved) {
      return;
    }
    if (saleReturn.refundMethod == RefundMethod.credit) {
      await _commitCreditAdjustment(saleReturn);
      return;
    }
    final allocated = saleReturn.refundLegs.fold<double>(
      0,
      (sum, leg) => sum + leg.amount,
    );
    if ((allocated - saleReturn.refundAmount).abs() > 0.01) {
      throw StateError('Refund allocation total does not match the return.');
    }

    for (final leg in saleReturn.refundLegs) {
      final paymentRows = await LocalDatabase.select(
        '''
        SELECT payment.id, payment.sale_id, payment.account_id, payment.amount,
               account.tenant_id, account.branch_id, account.is_active
        FROM sale_payments payment
        JOIN accounts account ON account.id = payment.account_id
        WHERE payment.id = ?
        LIMIT 1
        ''',
        [leg.originalPaymentId],
      );
      if (paymentRows.isEmpty) {
        throw StateError('Original refundable payment was not found.');
      }
      final payment = paymentRows.single;
      if (payment['sale_id'] != saleReturn.originalSaleId ||
          payment['account_id'] != leg.accountId ||
          payment['branch_id'] != saleReturn.branchId ||
          (payment['is_active'] as num).toInt() != 1) {
        throw StateError('Refund payment account context does not match.');
      }

      final priorRows = await LocalDatabase.select(
        '''
        SELECT COALESCE(SUM(amount), 0) AS refunded
        FROM sale_return_refund_legs
        WHERE original_payment_id = ?
          AND return_id <> ?
        ''',
        [leg.originalPaymentId, saleReturn.id],
      );
      final prior = (priorRows.single['refunded'] as num).toDouble();
      final paid = (payment['amount'] as num).toDouble();
      if (leg.amount <= 0 || prior + leg.amount > paid + 0.01) {
        throw StateError('Refund exceeds original payment capacity.');
      }

      final existing = await LocalDatabase.select(
        'SELECT * FROM sale_return_refund_legs WHERE id = ? LIMIT 1',
        [leg.id],
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['return_id'] != saleReturn.id ||
            row['original_payment_id'] != leg.originalPaymentId ||
            row['account_id'] != leg.accountId ||
            (row['amount'] as num).toDouble() != leg.amount ||
            row['ledger_transaction_id'] != leg.ledgerTransactionId) {
          throw StateError('Refund leg identity conflicts with existing data.');
        }
        continue;
      }

      final now = DateTime.now().toIso8601String();
      await LocalDatabase.execute(
        '''
        INSERT INTO account_transactions(
          id, tenant_id, branch_id, account_id, transaction_type,
          direction, amount, description, reference_type, reference_id,
          source_event_key, transaction_at, created_by, created_at
        )
        VALUES (?, ?, ?, ?, 'other', 'out', ?, ?, 'pos_sale_refund', ?,
                ?, ?, ?, ?)
        ''',
        [
          leg.ledgerTransactionId,
          payment['tenant_id'],
          saleReturn.branchId,
          leg.accountId,
          leg.amount,
          'POS sale refund',
          leg.id,
          'pos:return:${saleReturn.id}:payment:${leg.originalPaymentId}',
          saleReturn.createdAt.toIso8601String(),
          saleReturn.approvedBy ?? saleReturn.userId,
          now,
        ],
      );
      await LocalDatabase.execute(
        '''
        UPDATE accounts
        SET current_balance = current_balance - ?,
            updated_at = ?
        WHERE id = ?
        ''',
        [leg.amount, now, leg.accountId],
      );
      await LocalDatabase.execute(
        '''
        INSERT INTO sale_return_refund_legs(
          id, return_id, original_payment_id, account_id, amount,
          ledger_transaction_id
        ) VALUES (?, ?, ?, ?, ?, ?)
        ''',
        [
          leg.id,
          saleReturn.id,
          leg.originalPaymentId,
          leg.accountId,
          leg.amount,
          leg.ledgerTransactionId,
        ],
      );
    }
  }

  static Future<void> _commitCreditAdjustment(
    SaleReturnModel saleReturn,
  ) async {
    if (saleReturn.refundAmount <= 0) return;
    final existing = await LocalDatabase.select(
      'SELECT * FROM sale_return_credit_adjustments WHERE return_id = ? LIMIT 1',
      [saleReturn.id],
    );
    if (existing.isNotEmpty) {
      final row = existing.single;
      if (row['original_sale_id'] != saleReturn.originalSaleId ||
          (row['amount'] as num).toDouble() != saleReturn.refundAmount) {
        throw StateError(
          'Credit return identity conflicts with existing data.',
        );
      }
      return;
    }

    final saleRows = await LocalDatabase.select(
      'SELECT customer_id, branch_id FROM sales WHERE id = ? LIMIT 1',
      [saleReturn.originalSaleId],
    );
    if (saleRows.isEmpty ||
        saleRows.single['branch_id'] != saleReturn.branchId ||
        saleRows.single['customer_id'] == null) {
      throw StateError('Credit return requires the original customer.');
    }
    final customerId = saleRows.single['customer_id'] as String;
    final creditRows = await LocalDatabase.select(
      '''
      SELECT COALESCE(SUM(amount), 0) AS issued
      FROM sale_payments
      WHERE sale_id = ? AND method = 'credit'
      ''',
      [saleReturn.originalSaleId],
    );
    final priorRows = await LocalDatabase.select(
      '''
      SELECT COALESCE(SUM(amount), 0) AS reversed
      FROM sale_return_credit_adjustments
      WHERE original_sale_id = ?
      ''',
      [saleReturn.originalSaleId],
    );
    final issued = (creditRows.single['issued'] as num).toDouble();
    final reversed = (priorRows.single['reversed'] as num).toDouble();
    if (reversed + saleReturn.refundAmount > issued + 0.01) {
      throw StateError('Credit return exceeds original credit capacity.');
    }

    final customerRows = await LocalDatabase.select(
      'SELECT outstanding_balance FROM customers WHERE id = ? LIMIT 1',
      [customerId],
    );
    if (customerRows.isEmpty ||
        (customerRows.single['outstanding_balance'] as num).toDouble() + 0.01 <
            saleReturn.refundAmount) {
      throw StateError('Credit return exceeds customer outstanding balance.');
    }
    final now = DateTime.now().toIso8601String();
    await LocalDatabase.execute(
      '''
      INSERT INTO sale_return_credit_adjustments(
        id, return_id, original_sale_id, customer_id, amount, created_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        'credit:${saleReturn.id}',
        saleReturn.id,
        saleReturn.originalSaleId,
        customerId,
        saleReturn.refundAmount,
        now,
      ],
    );
    await LocalDatabase.execute(
      '''
      UPDATE customers
      SET outstanding_balance = outstanding_balance - ?
      WHERE id = ?
      ''',
      [saleReturn.refundAmount, customerId],
    );
  }
}
