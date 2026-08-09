import 'dart:convert';

import 'package:mobileshop_saas/core/local/local_database.dart';

import '../models/procurement_models.dart';
import '../models/supplier_sales_analytics_models.dart';
import '../../domain/supplier_accounting_contract.dart';

class ProcurementLocalStore {
  static Future<SupplierSalesSummary> loadSupplierSalesSummary({
    required String supplierId,
    required String branchId,
    required DateTime? dateFrom,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      WITH supplier_links AS (
        SELECT sp.product_id, counts.supplier_count
        FROM supplier_products sp
        JOIN (
          SELECT product_id, COUNT(DISTINCT supplier_id) AS supplier_count
          FROM supplier_products
          GROUP BY product_id
        ) counts ON counts.product_id = sp.product_id
        JOIN products p ON p.id = sp.product_id
        WHERE sp.supplier_id = ? AND p.branch_id = ? AND p.is_active = 1
      ),
      sale_lines AS (
        SELECT s.id AS sale_id, si.product_id,
          SUM(si.quantity) AS sold_quantity,
          SUM(si.line_total) AS revenue,
          SUM(COALESCE(si.cogs_total, si.unit_cost_at_sale * si.quantity, 0)) AS cost
        FROM sales s
        JOIN sale_items si ON si.sale_id = s.id
        WHERE s.branch_id = ? AND s.status = 'completed'
          AND (? IS NULL OR s.created_at >= ?)
        GROUP BY s.id, si.product_id
      ),
      returned AS (
        SELECT sri.original_sale_id AS sale_id, sri.product_id,
          SUM(sri.quantity) AS returned_quantity,
          SUM(sri.refund_amount) AS refund
        FROM sale_return_items sri
        JOIN sale_returns sr ON sr.id = sri.return_id
        WHERE sr.branch_id = ? AND sr.status = 'approved'
        GROUP BY sri.original_sale_id, sri.product_id
      ),
      eligible_net AS (
        SELECT sl.sale_id,
          MAX(sl.sold_quantity - COALESCE(r.returned_quantity, 0), 0) AS quantity,
          sl.revenue - COALESCE(r.refund, 0) AS revenue,
          CASE WHEN sl.sold_quantity = 0 THEN 0 ELSE
            sl.cost * MAX(sl.sold_quantity - COALESCE(r.returned_quantity, 0), 0)
              / sl.sold_quantity END AS cost
        FROM sale_lines sl
        LEFT JOIN returned r
          ON r.sale_id = sl.sale_id AND r.product_id = sl.product_id
        JOIN supplier_links link ON link.product_id = sl.product_id
        WHERE link.supplier_count = 1
      )
      SELECT
        (SELECT COUNT(*) FROM supplier_links) AS linked_product_count,
        (SELECT COUNT(*) FROM supplier_links WHERE supplier_count > 1)
          AS shared_product_count,
        COUNT(DISTINCT sale_id) AS sales_count,
        COALESCE(SUM(quantity), 0) AS units_sold,
        COALESCE(SUM(revenue), 0) AS sales_revenue,
        COALESCE(SUM(cost), 0) AS cost_of_sales,
        COALESCE(SUM(revenue), 0) - COALESCE(SUM(cost), 0) AS gross_profit,
        CASE WHEN COALESCE(SUM(revenue), 0) = 0 THEN 0 ELSE
          (SUM(revenue) - SUM(cost)) / SUM(revenue) * 100 END AS profit_margin
      FROM eligible_net
      ''',
      [
        supplierId,
        branchId,
        branchId,
        dateFrom?.toUtc().toIso8601String(),
        dateFrom?.toUtc().toIso8601String(),
        branchId,
      ],
    );
    return SupplierSalesSummary.fromMap(rows.first);
  }

  static Future<SupplierProductSalesPage> loadSupplierProductSalesPage({
    required String supplierId,
    required String branchId,
    required DateTime? dateFrom,
    required String search,
    required SupplierProfitFilter profitFilter,
    required SupplierAnalyticsSort sort,
    required int limit,
    required int offset,
  }) async {
    final searchPattern = '%${search.trim().toLowerCase()}%';
    final rows = await LocalDatabase.select(
      '''
      WITH supplier_links AS (
        SELECT sp.product_id, counts.supplier_count
        FROM supplier_products sp
        JOIN (
          SELECT product_id, COUNT(DISTINCT supplier_id) AS supplier_count
          FROM supplier_products GROUP BY product_id
        ) counts ON counts.product_id = sp.product_id
        JOIN products p ON p.id = sp.product_id
        WHERE sp.supplier_id = ? AND p.branch_id = ? AND p.is_active = 1
      ),
      sale_lines AS (
        SELECT s.id AS sale_id, si.product_id,
          SUM(si.quantity) AS sold_quantity, SUM(si.line_total) AS revenue,
          SUM(COALESCE(si.cogs_total, si.unit_cost_at_sale * si.quantity, 0)) AS cost
        FROM sales s JOIN sale_items si ON si.sale_id = s.id
        WHERE s.branch_id = ? AND s.status = 'completed'
          AND (? IS NULL OR s.created_at >= ?)
        GROUP BY s.id, si.product_id
      ),
      returned AS (
        SELECT sri.original_sale_id AS sale_id, sri.product_id,
          SUM(sri.quantity) AS returned_quantity, SUM(sri.refund_amount) AS refund
        FROM sale_return_items sri JOIN sale_returns sr ON sr.id = sri.return_id
        WHERE sr.branch_id = ? AND sr.status = 'approved'
        GROUP BY sri.original_sale_id, sri.product_id
      ),
      product_totals AS (
        SELECT sl.product_id,
          SUM(MAX(sl.sold_quantity - COALESCE(r.returned_quantity, 0), 0)) AS units_sold,
          SUM(sl.revenue - COALESCE(r.refund, 0)) AS sales_revenue,
          SUM(CASE WHEN sl.sold_quantity = 0 THEN 0 ELSE
            sl.cost * MAX(sl.sold_quantity - COALESCE(r.returned_quantity, 0), 0)
              / sl.sold_quantity END) AS cost_of_sales
        FROM sale_lines sl LEFT JOIN returned r
          ON r.sale_id = sl.sale_id AND r.product_id = sl.product_id
        GROUP BY sl.product_id
      ),
      analytics_rows AS (
        SELECT p.id AS product_id, p.name AS product_name, p.sku,
          COALESCE(i.quantity, 0) AS stock,
          CASE WHEN link.supplier_count = 1 THEN COALESCE(pt.units_sold, 0) ELSE 0 END AS units_sold,
          CASE WHEN link.supplier_count = 1 THEN COALESCE(pt.sales_revenue, 0) ELSE 0 END AS sales_revenue,
          CASE WHEN link.supplier_count = 1 THEN COALESCE(pt.cost_of_sales, 0) ELSE 0 END AS cost_of_sales,
          link.supplier_count > 1 AS is_shared
        FROM supplier_links link JOIN products p ON p.id = link.product_id
        LEFT JOIN inventory i ON i.product_id = p.id AND i.branch_id = ?
        LEFT JOIN product_totals pt ON pt.product_id = p.id
        WHERE ? = '%%' OR LOWER(p.name) LIKE ? OR LOWER(COALESCE(p.sku, '')) LIKE ?
          OR LOWER(COALESCE(p.barcode, '')) LIKE ?
      ),
      filtered AS (
        SELECT *, sales_revenue - cost_of_sales AS gross_profit,
          CASE WHEN sales_revenue = 0 THEN 0 ELSE
            (sales_revenue - cost_of_sales) / sales_revenue * 100 END AS profit_margin
        FROM analytics_rows
        WHERE ? = 'all' OR (? = 'profit' AND sales_revenue - cost_of_sales > 0)
          OR (? = 'loss' AND sales_revenue - cost_of_sales < 0)
          OR (? = 'unsold' AND units_sold = 0)
      )
      SELECT *, COUNT(*) OVER () AS total_count FROM filtered
      ORDER BY
        CASE WHEN ? = 'revenue_desc' THEN sales_revenue END DESC,
        CASE WHEN ? = 'units_desc' THEN units_sold END DESC,
        CASE WHEN ? = 'profit_desc' THEN gross_profit END DESC,
        CASE WHEN ? = 'profit_asc' THEN gross_profit END ASC,
        CASE WHEN ? = 'name_asc' THEN product_name END ASC,
        product_name ASC
      LIMIT ? OFFSET ?
      ''',
      [
        supplierId,
        branchId,
        branchId,
        dateFrom?.toUtc().toIso8601String(),
        dateFrom?.toUtc().toIso8601String(),
        branchId,
        branchId,
        searchPattern,
        searchPattern,
        searchPattern,
        searchPattern,
        profitFilter.value,
        profitFilter.value,
        profitFilter.value,
        profitFilter.value,
        sort.value,
        sort.value,
        sort.value,
        sort.value,
        sort.value,
        limit.clamp(1, 100),
        offset < 0 ? 0 : offset,
      ],
    );
    return SupplierProductSalesPage(
      items: rows.map(SupplierProductSalesRow.fromMap).toList(),
      total:
          rows.isEmpty ? 0 : (rows.first['total_count'] as num?)?.toInt() ?? 0,
    );
  }

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

  static Future<List<SupplierModel>> loadSuppliers(
    String tenantId,
    String branchId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM suppliers
      WHERE tenant_id = ?
        AND branch_id = ?
        AND is_active = 1
      ORDER BY name ASC
      ''',
      [tenantId, branchId],
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
      final linkedProductId = item.resolvedProductId ?? item.productId;
      if (linkedProductId != null) {
        await _saveSupplierProductLink(
          tenantId: po.tenantId,
          supplierId: po.supplierId,
          productId: linkedProductId,
          supplierSku: item.productSku,
          lastCost: item.actualUnitCost ?? item.negotiatedUnitCost,
        );
      }
    }
  }

  static Future<void> _saveSupplierProductLink({
    required String tenantId,
    required String supplierId,
    required String productId,
    String? supplierSku,
    double? lastCost,
  }) {
    return LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO supplier_products(
        id, tenant_id, supplier_id, product_id, supplier_sku,
        last_cost, created_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        '$supplierId:$productId',
        tenantId,
        supplierId,
        productId,
        supplierSku,
        lastCost,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  static Future<void> savePurchaseOrderItem(PurchaseOrderItemModel item) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO purchase_order_items(
        id, tenant_id, purchase_order_id, product_id, product_name,
        product_resolution, product_draft_json, resolved_product_id,
        product_sku, ordered_quantity, received_quantity,
        negotiated_unit_cost, actual_unit_cost, line_total, created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        item.id,
        item.tenantId,
        item.purchaseOrderId,
        item.productId,
        item.productName,
        item.productResolution.code,
        item.productDraft == null ? null : jsonEncode(item.productDraft),
        item.resolvedProductId,
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

  static Future<void> markPurchaseOrderCancelled(String poId) async {
    final now = DateTime.now().toIso8601String();
    await LocalDatabase.execute(
      '''
      UPDATE purchase_orders
      SET status = ?, cancelled_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      [PurchaseOrderStatus.cancelled.code, now, now, poId],
    );
  }

  /// Mirrors an already-committed online reversal into SQLite.
  static Future<void> reconcileReversedPurchaseOrderInventory({
    required String purchaseOrderId,
    required String branchId,
  }) async {
    await LocalDatabase.runInTransaction(() async {
      final rows = await LocalDatabase.select(
        '''
        SELECT product_id, item_resolution,
               SUM(received_quantity) AS received_quantity
        FROM goods_receipt_items
        WHERE purchase_order_id = ? AND product_id IS NOT NULL
        GROUP BY product_id, item_resolution
        ''',
        [purchaseOrderId],
      );
      final now = DateTime.now().toIso8601String();
      for (final row in rows) {
        final productId = row['product_id'] as String;
        final receivedQuantity =
            (row['received_quantity'] as num?)?.toInt() ?? 0;
        await LocalDatabase.execute(
          '''
          UPDATE inventory
          SET quantity = MAX(quantity - ?, 0), updated_at = ?
          WHERE branch_id = ? AND product_id = ?
          ''',
          [receivedQuantity, now, branchId, productId],
        );
      }
      await markPurchaseOrderCancelled(purchaseOrderId);
    });
  }

  static Future<void> applyReceiptLocally({
    required PurchaseOrderModel po,
    required String receiptId,
    required String receiptNo,
    required String userId,
    String? note,
    required List<GoodsReceiptItemInput> inputs,
  }) async {
    await LocalDatabase.runInTransaction(
      () => _applyReceiptWithinTransaction(
        po: po,
        receiptId: receiptId,
        receiptNo: receiptNo,
        userId: userId,
        note: note,
        inputs: inputs,
      ),
    );
  }

  static Future<void> _applyReceiptWithinTransaction({
    required PurchaseOrderModel po,
    required String receiptId,
    required String receiptNo,
    required String userId,
    String? note,
    required List<GoodsReceiptItemInput> inputs,
  }) async {
    final existing = await LocalDatabase.select(
      'SELECT * FROM goods_receipts WHERE id = ? LIMIT 1',
      [receiptId],
    );
    if (existing.isNotEmpty) {
      final row = existing.single;
      if (row['purchase_order_id'] != po.id ||
          row['supplier_id'] != po.supplierId ||
          row['receipt_no'] != receiptNo) {
        throw StateError('Goods receipt identity conflicts.');
      }
      return;
    }
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
      final inventoryProductId = switch (item.productResolution) {
        PurchaseProductResolution.existingProduct => item.productId,
        PurchaseProductResolution.createOnReceipt => item.resolvedProductId,
        PurchaseProductResolution.resolveOnReceipt => input.resolvedProductId,
        PurchaseProductResolution.directUse => null,
      };
      if (!SupplierAccountingContract.mayCompleteReceipt(
        resolution: item.productResolution,
        hasResolvedProduct: inventoryProductId != null,
      )) {
        throw StateError(
          'Choose or create an inventory product for ${item.productName}.',
        );
      }

      if (item.productResolution == PurchaseProductResolution.createOnReceipt) {
        final draft = item.productDraft;
        if (draft == null || inventoryProductId == null) {
          throw StateError('New product details are missing.');
        }
        await LocalDatabase.execute(
          '''
          INSERT OR IGNORE INTO products(
            id, tenant_id, branch_id, name, sku, sale_price, cost_price,
            imei_tracked, is_active, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?)
          ''',
          [
            inventoryProductId,
            po.tenantId,
            po.branchId,
            draft['name'] ?? item.productName,
            draft['sku'],
            (draft['sale_price'] as num?)?.toDouble() ?? 0,
            input.actualUnitCost,
            DateTime.now().toIso8601String(),
            DateTime.now().toIso8601String(),
          ],
        );
      }

      final newReceived = item.receivedQuantity + input.receivedQuantity;

      final updatedItem = PurchaseOrderItemModel(
        id: item.id,
        tenantId: item.tenantId,
        purchaseOrderId: item.purchaseOrderId,
        productId: item.productId,
        productResolution: item.productResolution,
        productDraft: item.productDraft,
        resolvedProductId: inventoryProductId ?? item.resolvedProductId,
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
        INSERT INTO goods_receipt_items(
          id, tenant_id, goods_receipt_id, purchase_order_id,
          purchase_order_item_id, product_id, item_resolution, item_name,
          received_quantity, actual_unit_cost, update_product_cost,
          line_total, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          '${receiptId}_${item.id}',
          po.tenantId,
          receiptId,
          po.id,
          item.id,
          inventoryProductId,
          item.productResolution.code,
          item.productName,
          input.receivedQuantity,
          input.actualUnitCost,
          input.updateProductCost ? 1 : 0,
          lineTotal,
          DateTime.now().toIso8601String(),
        ],
      );

      final productRows =
          inventoryProductId == null
              ? const <Map<String, dynamic>>[]
              : await LocalDatabase.select(
                'SELECT cost_price FROM products WHERE id = ? LIMIT 1',
                [inventoryProductId],
              );
      final currentCost =
          productRows.isEmpty
              ? null
              : (productRows.first['cost_price'] as num?)?.toDouble();
      final sameCost =
          currentCost != null &&
          (currentCost - input.actualUnitCost).abs() < 0.005;

      // A different-cost product variant is created atomically by the server.
      // While offline, do not corrupt the original product's stock or price;
      // the queued receipt will populate the correct variant after sync.
      if (inventoryProductId != null &&
          (sameCost ||
              item.productResolution ==
                  PurchaseProductResolution.createOnReceipt)) {
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
            inventoryProductId,
            input.receivedQuantity,
            DateTime.now().toIso8601String(),
          ],
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
      INSERT INTO goods_receipts(
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

    final now = DateTime.now().toIso8601String();
    await LocalDatabase.execute(
      '''
      INSERT INTO supplier_ledger_entries(
        id, tenant_id, branch_id, supplier_id, entry_type, direction,
        amount, source_event_key, reference_type, reference_id, description,
        occurred_at, created_by, created_at
      ) VALUES (?, ?, ?, ?, 'goods_receipt', 'increase', ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'supplier-ledger-receipt-$receiptId',
        po.tenantId,
        po.branchId,
        po.supplierId,
        total,
        'supplier:receipt:$receiptId',
        'goods_receipt',
        receiptId,
        'Goods received ${po.poNo}',
        now,
        userId,
        now,
      ],
    );
    await updateSupplierBalance(supplierId: po.supplierId, delta: total);
  }

  static Future<void> saveSupplierPayment(SupplierPaymentModel payment) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO supplier_payments(
        id, tenant_id, branch_id, supplier_id, purchase_order_id, amount,
        method, account_id, ledger_transaction_id, note, paid_by, paid_at,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        payment.id,
        payment.tenantId,
        payment.branchId,
        payment.supplierId,
        payment.purchaseOrderId,
        payment.amount,
        payment.method,
        payment.accountId,
        payment.ledgerTransactionId,
        payment.note,
        payment.paidBy,
        payment.paidAt?.toIso8601String(),
        payment.createdAt?.toIso8601String(),
      ],
    );
  }

  static Future<List<SupplierPaymentModel>> loadSupplierPayments(
    String supplierId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT * FROM supplier_payments
      WHERE supplier_id = ?
      ORDER BY paid_at DESC, created_at DESC
      ''',
      [supplierId],
    );
    return rows.map(SupplierPaymentModel.fromMap).toList();
  }

  static Future<List<SupplierLedgerEntryModel>> loadSupplierLedger(
    String supplierId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM supplier_ledger_entries
      WHERE supplier_id = ?
        AND (? IS NULL OR occurred_at >= ?)
        AND (? IS NULL OR occurred_at < ?)
      ORDER BY occurred_at DESC, created_at DESC, id DESC
      ''',
      [
        supplierId,
        from?.toIso8601String(),
        from?.toIso8601String(),
        to?.toIso8601String(),
        to?.add(const Duration(days: 1)).toIso8601String(),
      ],
    );
    return rows.map(SupplierLedgerEntryModel.fromMap).toList();
  }

  static Future<void> saveSupplierLedgerEntry(
    SupplierLedgerEntryModel entry,
  ) async {
    final map = entry.toMap();
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO supplier_ledger_entries(
        id, tenant_id, branch_id, supplier_id, entry_type, direction,
        amount, source_event_key, reference_type, reference_id, description,
        occurred_at, created_by, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        map['id'],
        map['tenant_id'],
        map['branch_id'],
        map['supplier_id'],
        map['entry_type'],
        map['direction'],
        map['amount'],
        map['source_event_key'],
        map['reference_type'],
        map['reference_id'],
        map['description'],
        map['occurred_at'],
        map['created_by'],
        map['created_at'],
      ],
    );
  }

  static Future<double> calculateSupplierPayable(String supplierId) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT COALESCE(SUM(
        CASE WHEN direction = 'increase' THEN amount ELSE -amount END
      ), 0) AS payable
      FROM supplier_ledger_entries
      WHERE supplier_id = ?
      ''',
      [supplierId],
    );
    return (rows.single['payable'] as num).toDouble();
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
