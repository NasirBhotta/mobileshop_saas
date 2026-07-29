import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/accounts/data/models/account_models.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_payment_account_policy.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';

class SupplierPaymentLocalCommitter {
  const SupplierPaymentLocalCommitter._();

  static Future<void> commit(SupplierPaymentModel payment) async {
    await LocalDatabase.runInTransaction(() async {
      final existing = await LocalDatabase.select(
        'SELECT * FROM supplier_payments WHERE id = ? LIMIT 1',
        [payment.id],
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['supplier_id'] != payment.supplierId ||
            row['purchase_order_id'] != payment.purchaseOrderId ||
            (row['amount'] as num).toDouble() != payment.amount ||
            row['account_id'] != payment.accountId ||
            row['ledger_transaction_id'] != payment.ledgerTransactionId) {
          throw StateError('Supplier payment identity conflicts.');
        }
        return;
      }
      final accountId = payment.accountId;
      final ledgerId = payment.ledgerTransactionId;
      if (accountId == null || ledgerId == null || payment.amount <= 0) {
        throw StateError('Supplier payment account linkage is incomplete.');
      }

      final accountRows = await LocalDatabase.select(
        'SELECT * FROM accounts WHERE id = ? LIMIT 1',
        [accountId],
      );
      if (accountRows.isEmpty) throw StateError('Paying account not found.');
      final account = AccountModel.fromMap(accountRows.single);
      final method = PaymentMethodX.fromCode(payment.method ?? 'cash');
      if (account.tenantId != payment.tenantId ||
          account.branchId != payment.branchId ||
          !PosPaymentAccountPolicy.isCompatible(method, account)) {
        throw StateError('Supplier paying account is incompatible.');
      }
      if (account.currentBalance + 0.01 < payment.amount) {
        throw StateError('Paying account balance is insufficient.');
      }

      final supplierRows = await LocalDatabase.select(
        'SELECT * FROM suppliers WHERE id = ? LIMIT 1',
        [payment.supplierId],
      );
      if (supplierRows.isEmpty ||
          supplierRows.single['tenant_id'] != payment.tenantId) {
        throw StateError('Supplier context is invalid.');
      }
      final outstanding =
          (supplierRows.single['outstanding_balance'] as num).toDouble();
      if (outstanding + 0.01 < payment.amount) {
        throw StateError('Payment exceeds supplier outstanding balance.');
      }
      final purchaseOrderId = payment.purchaseOrderId;
      if (purchaseOrderId != null) {
        final poRows = await LocalDatabase.select(
          '''
        SELECT * FROM purchase_orders
        WHERE id = ? AND supplier_id = ? AND branch_id = ?
        LIMIT 1
        ''',
          [purchaseOrderId, payment.supplierId, payment.branchId],
        );
        if (poRows.isEmpty) throw StateError('Purchase order not found.');
        final paidRows = await LocalDatabase.select(
          '''
        SELECT COALESCE(SUM(amount), 0) AS paid
        FROM supplier_payments WHERE purchase_order_id = ?
        ''',
          [purchaseOrderId],
        );
        final received =
            (poRows.single['total_received_cost'] as num?)?.toDouble() ?? 0;
        final paid = (paidRows.single['paid'] as num).toDouble();
        if (received - paid + 0.01 < payment.amount) {
          throw StateError('Payment exceeds purchase order pending amount.');
        }
      }

      await LocalDatabase.execute(
        '''
        INSERT INTO supplier_payments(
          id, tenant_id, branch_id, supplier_id, purchase_order_id, amount,
          method, account_id,
          ledger_transaction_id, note, paid_by, paid_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          payment.id,
          payment.tenantId,
          payment.branchId,
          payment.supplierId,
          purchaseOrderId,
          payment.amount,
          payment.method,
          accountId,
          ledgerId,
          payment.note,
          payment.paidBy,
          payment.paidAt?.toIso8601String(),
          payment.createdAt?.toIso8601String(),
        ],
      );
      await LocalDatabase.execute(
        '''
        UPDATE suppliers
        SET outstanding_balance = MAX(0, outstanding_balance - ?),
            updated_at = ?
        WHERE id = ?
        ''',
        [payment.amount, DateTime.now().toIso8601String(), payment.supplierId],
      );
      final now = DateTime.now().toIso8601String();
      await LocalDatabase.execute(
        '''
        INSERT INTO supplier_ledger_entries(
          id, tenant_id, branch_id, supplier_id, entry_type, direction,
          amount, source_event_key, reference_type, reference_id, description,
          occurred_at, created_by, created_at
        ) VALUES (?, ?, ?, ?, 'supplier_payment', 'decrease', ?, ?, ?, ?, ?,
                  ?, ?, ?)
        ''',
        [
          'supplier-ledger-payment-${payment.id}',
          payment.tenantId,
          payment.branchId,
          payment.supplierId,
          payment.amount,
          'supplier:payment:${payment.id}',
          'supplier_payment',
          payment.id,
          'Supplier payment',
          payment.paidAt?.toIso8601String() ?? now,
          payment.paidBy,
          now,
        ],
      );
      await LocalDatabase.execute(
        '''
        INSERT INTO account_transactions(
          id, tenant_id, branch_id, account_id, transaction_type, direction,
          amount, description, reference_type, reference_id, source_event_key,
          transaction_at, created_by, created_at
        ) VALUES (?, ?, ?, ?, 'supplier_payment', 'out', ?,
                  'Supplier payment', 'supplier_payment', ?, ?, ?, ?, ?)
        ''',
        [
          ledgerId,
          payment.tenantId,
          payment.branchId,
          accountId,
          payment.amount,
          payment.id,
          'supplier:payment:${payment.id}',
          payment.paidAt?.toIso8601String() ?? now,
          payment.paidBy,
          now,
        ],
      );
      await LocalDatabase.execute(
        '''
        UPDATE accounts
        SET current_balance = current_balance - ?, updated_at = ?
        WHERE id = ?
        ''',
        [payment.amount, now, accountId],
      );
    });
  }
}
