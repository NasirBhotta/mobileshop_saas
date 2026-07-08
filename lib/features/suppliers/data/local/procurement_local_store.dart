import 'package:mobileshop_saas/core/local/local_database.dart';

import '../models/procurement_models.dart';

class ProcurementLocalStore {
  static Future<void> saveSupplier(SupplierModel supplier) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO suppliers(
        id, tenant_id, branch_id, name, contact_person, phone, email,
        address, city, payment_terms, outstanding_balance, notes,
        is_active, created_by, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        supplier.id,
        supplier.tenantId,
        supplier.branchId,
        supplier.name,
        supplier.contactPerson,
        supplier.phone,
        supplier.email,
        supplier.address,
        supplier.city,
        supplier.paymentTerms,
        supplier.outstandingBalance,
        supplier.notes,
        supplier.isActive ? 1 : 0,
        supplier.createdBy,
        supplier.createdAt?.toIso8601String(),
        supplier.updatedAt?.toIso8601String(),
      ],
    );
  }

  static Future<List<SupplierModel>> loadSuppliers(String tenantId) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM suppliers
      WHERE tenant_id = ?
        AND is_active = 1
      ORDER BY name ASC
      ''',
      [tenantId],
    );

    return rows.map(SupplierModel.fromMap).toList();
  }

  static Future<SupplierModel?> loadSupplierById(String supplierId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM suppliers WHERE id = ? LIMIT 1',
      [supplierId],
    );

    if (rows.isEmpty) return null;
    return SupplierModel.fromMap(rows.first);
  }

  static Future<void> updateSupplierBalance({
    required String supplierId,
    required double delta,
  }) async {
    await LocalDatabase.execute(
      '''
      UPDATE suppliers
      SET outstanding_balance =
        CASE
          WHEN outstanding_balance + ? < 0 THEN 0
          ELSE outstanding_balance + ?
        END,
        updated_at = ?
      WHERE id = ?
      ''',
      [delta, delta, DateTime.now().toIso8601String(), supplierId],
    );
  }

  static Future<void> savePurchaseOrder(PurchaseOrderModel po) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO purchase_orders(
        id, tenant_id, branch_id, supplier_id, po_no, status,
        expected_delivery_at, notes, total_expected_cost, total_received_cost,
        created_by, sent_at, cancelled_at, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        po.id,
        po.tenantId,
        po.branchId,
        po.supplierId,
        po.poNo,
        po.status.code,
        po.expectedDeliveryAt?.toIso8601String(),
        po.notes,
        po.totalExpectedCost,
        po.totalReceivedCost,
        po.createdBy,
        po.sentAt?.toIso8601String(),
        po.cancelledAt?.toIso8601String(),
        po.createdAt?.toIso8601String(),
        po.updatedAt?.toIso8601String(),
      ],
    );

    for (final item in po.items) {
      await savePurchaseOrderItem(item);
    }
  }

  static Future<void> savePurchaseOrderItem(PurchaseOrderItemModel item) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO purchase_order_items(
        id, tenant_id, purchase_order_id, product_id, product_name,
        product_sku, ordered_quantity, received_quantity,
        negotiated_unit_cost, actual_unit_cost, line_total, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        item.id,
        item.tenantId,
        item.purchaseOrderId,
        item.productId,
        item.productName,
        item.productSku,
        item.orderedQuantity,
        item.receivedQuantity,
        item.negotiatedUnitCost,
        item.actualUnitCost,
        item.lineTotal,
        item.createdAt?.toIso8601String(),
      ],
    );
  }

  static Future<List<PurchaseOrderModel>> loadPurchaseOrders(
    String branchId, {
    PurchaseOrderStatus? status,
  }) async {
    final rows =
        status == null
            ? await LocalDatabase.select(
              '''
            SELECT *
            FROM purchase_orders
            WHERE branch_id = ?
            ORDER BY created_at DESC
            ''',
              [branchId],
            )
            : await LocalDatabase.select(
              '''
            SELECT *
            FROM purchase_orders
            WHERE branch_id = ?
              AND status = ?
            ORDER BY created_at DESC
            ''',
              [branchId, status.code],
            );

    final result = <PurchaseOrderModel>[];

    for (final row in rows) {
      final items = await loadPurchaseOrderItems(row['id'] as String);
      result.add(PurchaseOrderModel.fromMap(row, items: items));
    }

    return result;
  }

  static Future<PurchaseOrderModel?> loadPurchaseOrderById(String poId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM purchase_orders WHERE id = ? LIMIT 1',
      [poId],
    );

    if (rows.isEmpty) return null;

    final items = await loadPurchaseOrderItems(poId);
    return PurchaseOrderModel.fromMap(rows.first, items: items);
  }

  static Future<List<PurchaseOrderItemModel>> loadPurchaseOrderItems(
    String poId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM purchase_order_items
      WHERE purchase_order_id = ?
      ORDER BY created_at ASC
      ''',
      [poId],
    );

    return rows.map(PurchaseOrderItemModel.fromMap).toList();
  }

  static Future<void> markPurchaseOrderSent(PurchaseOrderModel po) async {
    await savePurchaseOrder(
      po.copyWith(status: PurchaseOrderStatus.sent, sentAt: DateTime.now()),
    );
  }

  static Future<void> applyReceiptLocally({
    required PurchaseOrderModel po,
    required String receiptId,
    required String receiptNo,
    required String userId,
    String? note,
    required List<GoodsReceiptItemInput> inputs,
  }) async {
    double total = 0;
    final updatedItems = <PurchaseOrderItemModel>[];

    for (final item in po.items) {
      final input =
          inputs.where((e) => e.purchaseOrderItemId == item.id).firstOrNull;

      if (input == null || input.receivedQuantity <= 0) {
        updatedItems.add(item);
        continue;
      }

      if (input.receivedQuantity > item.remainingQuantity) {
        throw Exception('Received quantity cannot exceed ordered quantity.');
      }

      final lineTotal = input.receivedQuantity * input.actualUnitCost;
      total += lineTotal;

      final newReceived = item.receivedQuantity + input.receivedQuantity;

      final updatedItem = PurchaseOrderItemModel(
        id: item.id,
        tenantId: item.tenantId,
        purchaseOrderId: item.purchaseOrderId,
        productId: item.productId,
        productName: item.productName,
        productSku: item.productSku,
        orderedQuantity: item.orderedQuantity,
        receivedQuantity: newReceived,
        negotiatedUnitCost: item.negotiatedUnitCost,
        actualUnitCost: input.actualUnitCost,
        lineTotal: item.lineTotal,
        createdAt: item.createdAt,
      );

      updatedItems.add(updatedItem);
      await savePurchaseOrderItem(updatedItem);

      await LocalDatabase.execute(
        '''
        INSERT INTO inventory(branch_id, product_id, quantity, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(branch_id, product_id)
        DO UPDATE SET
          quantity = quantity + excluded.quantity,
          updated_at = excluded.updated_at
        ''',
        [
          po.branchId,
          item.productId,
          input.receivedQuantity,
          DateTime.now().toIso8601String(),
        ],
      );

      if (input.updateProductCost) {
        await LocalDatabase.execute(
          '''
          UPDATE products
          SET cost_price = ?
          WHERE id = ?
          ''',
          [input.actualUnitCost, item.productId],
        );
      }
    }

    if (total <= 0) {
      throw Exception('Received quantity must be greater than zero.');
    }

    final allReceived = updatedItems.every(
      (item) => item.remainingQuantity == 0,
    );
    final anyReceived = updatedItems.any((item) => item.receivedQuantity > 0);

    final newStatus =
        allReceived
            ? PurchaseOrderStatus.received
            : anyReceived
            ? PurchaseOrderStatus.partiallyReceived
            : po.status;

    await savePurchaseOrder(
      po.copyWith(
        status: newStatus,
        totalReceivedCost: po.totalReceivedCost + total,
        items: updatedItems,
      ),
    );

    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO goods_receipts(
        id, tenant_id, branch_id, purchase_order_id, supplier_id,
        receipt_no, note, total_received_value, received_by, received_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        receiptId,
        po.tenantId,
        po.branchId,
        po.id,
        po.supplierId,
        receiptNo,
        note,
        total,
        userId,
        DateTime.now().toIso8601String(),
      ],
    );

    await updateSupplierBalance(supplierId: po.supplierId, delta: total);
  }

  static Future<void> saveSupplierPayment(SupplierPaymentModel payment) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO supplier_payments(
        id, tenant_id, branch_id, supplier_id, amount,
        method, note, paid_by, paid_at, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        payment.id,
        payment.tenantId,
        payment.branchId,
        payment.supplierId,
        payment.amount,
        payment.method,
        payment.note,
        payment.paidBy,
        payment.paidAt?.toIso8601String(),
        payment.createdAt?.toIso8601String(),
      ],
    );

    await updateSupplierBalance(
      supplierId: payment.supplierId,
      delta: -payment.amount,
    );
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
