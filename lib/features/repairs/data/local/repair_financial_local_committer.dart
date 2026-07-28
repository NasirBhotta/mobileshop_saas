import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';

class RepairFinancialLocalCommitter {
  static Future<void> complete({
    required RepairTicketModel ticket,
    required String eventId,
    required String userId,
    required double customerCharge,
    double serviceCharge = 0,
    double discount = 0,
    double commission = 0,
    double otherDirectCost = 0,
  }) {
    return LocalDatabase.runInTransaction(() async {
      final sourceKey = 'repair:completion:$eventId';
      if (await _eventExists(sourceKey)) return;
      if (customerCharge < 0 ||
          serviceCharge < 0 ||
          discount < 0 ||
          commission < 0 ||
          otherDirectCost < 0) {
        throw StateError('Repair financial amounts cannot be negative.');
      }
      final ticketRows = await LocalDatabase.select(
        'SELECT * FROM repair_tickets WHERE id = ? LIMIT 1',
        [ticket.id],
      );
      if (ticketRows.isEmpty) throw StateError('Repair ticket not found.');
      final current = ticketRows.single;
      if (current['tenant_id'] != ticket.tenantId ||
          current['branch_id'] != ticket.branchId ||
          const {
            'completed',
            'delivered',
            'cancelled',
          }.contains(current['status'])) {
        throw StateError('Ticket cannot be completed.');
      }
      final paidRows = await LocalDatabase.select(
        'SELECT COALESCE(SUM(amount), 0) AS paid FROM repair_payments WHERE ticket_id = ?',
        [ticket.id],
      );
      final paid = (paidRows.single['paid'] as num).toDouble();
      if (paid > customerCharge + 0.01) {
        throw StateError('Customer charge cannot be below payments received.');
      }

      var inventoryCost = 0.0;
      var directCost = 0.0;
      final parts = await LocalDatabase.select(
        "SELECT * FROM repair_parts WHERE ticket_id = ? AND state = 'planned'",
        [ticket.id],
      );
      for (final part in parts) {
        final quantity = (part['quantity'] as num).toInt();
        final cost = (part['unit_cost_snapshot'] as num).toDouble();
        if (part['source_type'] == 'inventory') {
          final productId = part['product_id'] as String?;
          final inventory = await LocalDatabase.select(
            'SELECT quantity FROM inventory WHERE branch_id = ? AND product_id = ? LIMIT 1',
            [ticket.branchId, productId],
          );
          if (productId == null ||
              inventory.isEmpty ||
              (inventory.single['quantity'] as num).toInt() < quantity) {
            throw StateError('Insufficient repair-part stock.');
          }
          await LocalDatabase.execute(
            'UPDATE inventory SET quantity = quantity - ?, updated_at = ? WHERE branch_id = ? AND product_id = ?',
            [quantity, _now(), ticket.branchId, productId],
          );
          inventoryCost += quantity * cost;
        } else {
          directCost += quantity * cost;
          if (part['settlement_type'] == 'supplier_payable') {
            final supplierId = part['supplier_id'] as String?;
            if (supplierId == null) {
              throw StateError('Direct-part supplier is required.');
            }
            await _postSupplierEntry(
              id: 'repair-direct-${part['id']}',
              ticket: ticket,
              supplierId: supplierId,
              userId: userId,
              type: 'goods_receipt',
              direction: 'increase',
              amount: quantity * cost,
              sourceKey: 'repair:direct-part:${part['id']}',
              referenceId: part['id'] as String,
              description: 'Direct repair part',
            );
            await LocalDatabase.execute(
              'UPDATE suppliers SET outstanding_balance = outstanding_balance + ?, updated_at = ? WHERE id = ?',
              [quantity * cost, _now(), supplierId],
            );
          }
        }
        await LocalDatabase.execute(
          "UPDATE repair_parts SET state = 'consumed', consumed_at = ?, updated_at = ? WHERE id = ?",
          [_now(), _now(), part['id']],
        );
      }
      final profit =
          customerCharge -
          inventoryCost -
          directCost -
          commission -
          otherDirectCost;
      await _insertEvent(
        id: eventId,
        ticket: ticket,
        userId: userId,
        type: 'completion',
        sourceKey: sourceKey,
        revenue: customerCharge,
        inventoryCost: inventoryCost,
        directCost: directCost,
        commission: commission,
        otherDirectCost: otherDirectCost,
        profit: profit,
      );
      await LocalDatabase.execute(
        '''
        UPDATE repair_tickets SET status = 'completed',
          customer_charge = ?, total_cost = ?, service_charge = ?,
          discount_amount = ?, parts_cost = ?, labor_cost = ?,
          per_job_commission = ?, other_direct_cost = ?,
          completed_at = ?, finalized_at = ?, updated_at = ?
        WHERE id = ?
        ''',
        [
          customerCharge,
          customerCharge,
          serviceCharge,
          discount,
          inventoryCost + directCost,
          commission,
          commission,
          otherDirectCost,
          _now(),
          _now(),
          _now(),
          ticket.id,
        ],
      );
      await _insertStatusLog(
        id: '$eventId-status',
        ticket: ticket,
        userId: userId,
        oldStatus: current['status'] as String,
        newStatus: 'completed',
      );
    });
  }

  static Future<void> cancel({
    required RepairTicketModel ticket,
    required String eventId,
    required String userId,
  }) {
    return LocalDatabase.runInTransaction(() async {
      final ticketRows = await LocalDatabase.select(
        'SELECT * FROM repair_tickets WHERE id = ? LIMIT 1',
        [ticket.id],
      );
      if (ticketRows.isEmpty) throw StateError('Repair ticket not found.');
      final current = ticketRows.single;
      if (current['status'] == 'cancelled') return;
      final paid = await LocalDatabase.select(
        'SELECT COALESCE(SUM(amount), 0) AS paid FROM repair_payments WHERE ticket_id = ?',
        [ticket.id],
      );
      if ((paid.single['paid'] as num).toDouble() > 0) {
        throw StateError('Refund or retain customer credit first.');
      }
      if (current['status'] == 'completed' ||
          current['status'] == 'delivered') {
        final sourceKey = 'repair:reversal:$eventId';
        if (await _eventExists(sourceKey)) return;
        final completion = await LocalDatabase.select(
          "SELECT * FROM repair_financial_events WHERE ticket_id = ? AND event_type = 'completion' ORDER BY occurred_at DESC LIMIT 1",
          [ticket.id],
        );
        if (completion.isEmpty) {
          throw StateError('Completion snapshot is missing.');
        }
        final parts = await LocalDatabase.select(
          "SELECT * FROM repair_parts WHERE ticket_id = ? AND state = 'consumed'",
          [ticket.id],
        );
        for (final part in parts) {
          if (part['source_type'] == 'inventory') {
            await LocalDatabase.execute(
              '''
              INSERT INTO inventory(branch_id, product_id, quantity, updated_at)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(branch_id, product_id) DO UPDATE SET
                quantity = quantity + excluded.quantity,
                updated_at = excluded.updated_at
              ''',
              [ticket.branchId, part['product_id'], part['quantity'], _now()],
            );
          }
          if (part['source_type'] == 'direct_purchase' &&
              part['settlement_type'] == 'supplier_payable') {
            final supplierId = part['supplier_id'] as String;
            final amount =
                (part['quantity'] as num).toInt() *
                (part['unit_cost_snapshot'] as num).toDouble();
            final supplier = await LocalDatabase.select(
              'SELECT outstanding_balance FROM suppliers WHERE id = ? LIMIT 1',
              [supplierId],
            );
            if (supplier.isEmpty ||
                (supplier.single['outstanding_balance'] as num).toDouble() <
                    amount) {
              throw StateError(
                'Resolve paid supplier amount before repair cancellation.',
              );
            }
            await _postSupplierEntry(
              id: 'repair-direct-reversal-${part['id']}',
              ticket: ticket,
              supplierId: supplierId,
              userId: userId,
              type: 'credit_note',
              direction: 'decrease',
              amount: amount,
              sourceKey: 'repair:direct-part-reversal:${part['id']}',
              referenceId: part['id'] as String,
              description: 'Cancelled direct repair part',
            );
            await LocalDatabase.execute(
              '''
              UPDATE suppliers SET outstanding_balance =
                outstanding_balance - ?,
                updated_at = ? WHERE id = ?
              ''',
              [amount, _now(), supplierId],
            );
          }
          await LocalDatabase.execute(
            "UPDATE repair_parts SET state = 'reversed', reversed_at = ?, updated_at = ? WHERE id = ?",
            [_now(), _now(), part['id']],
          );
        }
        final event = completion.single;
        await _insertEvent(
          id: eventId,
          ticket: ticket,
          userId: userId,
          type: 'reversal',
          sourceKey: sourceKey,
          revenue: -(event['revenue_amount'] as num).toDouble(),
          inventoryCost: -(event['inventory_cost'] as num).toDouble(),
          directCost: -(event['direct_parts_cost'] as num).toDouble(),
          commission: -(event['commission_cost'] as num).toDouble(),
          otherDirectCost: -(event['other_direct_cost'] as num).toDouble(),
          profit: -(event['gross_profit'] as num).toDouble(),
          reversalOf: event['id'] as String,
        );
      }
      await LocalDatabase.execute(
        '''
        UPDATE repair_tickets SET status = 'cancelled',
          reversed_at = CASE WHEN finalized_at IS NULL THEN NULL ELSE ? END,
          updated_at = ? WHERE id = ?
        ''',
        [_now(), _now(), ticket.id],
      );
      await _insertStatusLog(
        id: '$eventId-status',
        ticket: ticket,
        userId: userId,
        oldStatus: current['status'] as String,
        newStatus: 'cancelled',
      );
    });
  }

  static Future<bool> _eventExists(String sourceKey) async =>
      (await LocalDatabase.select(
        'SELECT 1 FROM repair_financial_events WHERE source_event_key = ? LIMIT 1',
        [sourceKey],
      )).isNotEmpty;

  static Future<void> _insertEvent({
    required String id,
    required RepairTicketModel ticket,
    required String userId,
    required String type,
    required String sourceKey,
    required double revenue,
    required double inventoryCost,
    required double directCost,
    required double commission,
    required double otherDirectCost,
    required double profit,
    String? reversalOf,
  }) async {
    await LocalDatabase.execute(
      '''
      INSERT INTO repair_financial_events(
        id, tenant_id, branch_id, ticket_id, event_type, source_event_key,
        revenue_amount, inventory_cost, direct_parts_cost, commission_cost,
        other_direct_cost, gross_profit, reversal_of_event_id,
        occurred_at, created_by, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        ticket.tenantId,
        ticket.branchId,
        ticket.id,
        type,
        sourceKey,
        revenue,
        inventoryCost,
        directCost,
        commission,
        otherDirectCost,
        profit,
        reversalOf,
        _now(),
        userId,
        _now(),
      ],
    );
  }

  static String _now() => DateTime.now().toIso8601String();

  static Future<void> _insertStatusLog({
    required String id,
    required RepairTicketModel ticket,
    required String userId,
    required String oldStatus,
    required String newStatus,
  }) {
    return LocalDatabase.execute(
      '''
      INSERT OR IGNORE INTO repair_status_logs(
        id, ticket_id, tenant_id, branch_id, old_status, new_status,
        changed_by, note, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        ticket.id,
        ticket.tenantId,
        ticket.branchId,
        oldStatus,
        newStatus,
        userId,
        'Repair financial $newStatus',
        _now(),
      ],
    );
  }

  static Future<void> _postSupplierEntry({
    required String id,
    required RepairTicketModel ticket,
    required String supplierId,
    required String userId,
    required String type,
    required String direction,
    required double amount,
    required String sourceKey,
    required String referenceId,
    required String description,
  }) {
    return LocalDatabase.execute(
      '''
      INSERT OR IGNORE INTO supplier_ledger_entries(
        id, tenant_id, branch_id, supplier_id, entry_type, direction,
        amount, source_event_key, reference_type, reference_id, description,
        occurred_at, created_by, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'repair_part', ?, ?, ?, ?, ?)
      ''',
      [
        id,
        ticket.tenantId,
        ticket.branchId,
        supplierId,
        type,
        direction,
        amount,
        sourceKey,
        referenceId,
        description,
        _now(),
        userId,
        _now(),
      ],
    );
  }
}
