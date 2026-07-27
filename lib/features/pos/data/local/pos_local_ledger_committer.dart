import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_payment_account_policy.dart';

class PosLocalLedgerCommitter {
  const PosLocalLedgerCommitter._();

  static Future<void> commit(SaleModel sale) async {
    await LocalDatabase.runInTransaction(() async {
      for (final payment in sale.payments) {
        if (!PosPaymentAccountPolicy.requiresAccount(payment.method)) continue;
        await _validatePaymentAccount(sale: sale, accountId: payment.accountId);
      }

      await LocalStore.saveSale(sale);

      for (final payment in sale.payments) {
        if (!PosPaymentAccountPolicy.requiresAccount(payment.method)) continue;
        final paymentId = payment.id;
        final ledgerId = payment.ledgerTransactionId;
        final accountId = payment.accountId;
        if (paymentId == null || ledgerId == null || accountId == null) {
          throw StateError('POS payment ledger identity is incomplete.');
        }

        final accountRows = await LocalDatabase.select(
          '''
          SELECT tenant_id
          FROM accounts
          WHERE id = ?
          LIMIT 1
          ''',
          [accountId],
        );
        final tenantId = accountRows.single['tenant_id'] as String;
        final sourceEventKey = 'pos:sale:${sale.id}:payment:$paymentId';
        final existing = await LocalDatabase.select(
          '''
          SELECT id, tenant_id, branch_id, account_id, transaction_type,
                 direction, amount, reference_id
          FROM account_transactions
          WHERE id = ? OR source_event_key = ?
          LIMIT 1
          ''',
          [ledgerId, sourceEventKey],
        );

        if (existing.isNotEmpty) {
          final row = existing.single;
          if (row['id'] != ledgerId ||
              row['tenant_id'] != tenantId ||
              row['branch_id'] != sale.branchId ||
              row['account_id'] != accountId ||
              row['transaction_type'] != 'sale' ||
              row['direction'] != 'in' ||
              (row['amount'] as num).toDouble() != payment.amount ||
              row['reference_id'] != paymentId) {
            throw StateError(
              'POS payment ledger identity conflicts with existing data.',
            );
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
          VALUES (?, ?, ?, ?, 'sale', 'in', ?, ?, 'pos_sale_payment', ?,
                  ?, ?, ?, ?)
          ''',
          [
            ledgerId,
            tenantId,
            sale.branchId,
            accountId,
            payment.amount,
            'POS ${payment.method.label} payment',
            paymentId,
            sourceEventKey,
            sale.createdAt?.toIso8601String() ?? now,
            sale.userId,
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
          [payment.amount, now, accountId],
        );
      }
    });
  }

  static Future<void> _validatePaymentAccount({
    required SaleModel sale,
    required String? accountId,
  }) async {
    if (accountId == null) {
      throw StateError('POS payment account is missing.');
    }
    final rows = await LocalDatabase.select(
      '''
      SELECT branch_id, is_active
      FROM accounts
      WHERE id = ?
      LIMIT 1
      ''',
      [accountId],
    );
    if (rows.isEmpty ||
        rows.single['branch_id'] != sale.branchId ||
        (rows.single['is_active'] as num).toInt() != 1) {
      throw StateError('POS payment account is inactive or cross-branch.');
    }
  }
}
