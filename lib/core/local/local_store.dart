import 'dart:convert';

import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/features/pos/data/models/cart_item_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_dashboard_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/held_cart_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/inventory_unit_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_status_log_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';

import '../../features/inventory/data/models/category_model.dart';
import '../../features/inventory/data/models/product_model.dart';
import '../../features/onboarding/data/models/shop_setup_model.dart';
import 'local_database.dart';

class LocalStore {
  const LocalStore._();

  static Future<void> saveProfile(
    String userId,
    Map<String, dynamic> profile,
  ) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO users(
        id, tenant_id, branch_id, full_name, email, phone, role
      ) VALUES(?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        userId,
        profile['tenant_id'],
        profile['branch_id'],
        profile['full_name'],
        profile['email'],
        profile['phone'],
        profile['role'],
      ],
    );
  }

  static Future<Map<String, dynamic>?> loadProfile(String userId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM users WHERE id = ?',
      [userId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<void> saveTenant(
    String tenantId,
    Map<String, dynamic> tenant,
  ) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO tenants(
        id, shop_name, business_type, branch_count, plan, status,
        setup_complete, created_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        tenantId,
        tenant['shop_name'],
        tenant['business_type'],
        tenant['branch_count'],
        tenant['plan'],
        tenant['status'],
        tenant['setup_complete'] == true ? 1 : 0,
        tenant['created_at'],
      ],
    );
  }

  static Future<Map<String, dynamic>?> loadTenant(String tenantId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM tenants WHERE id = ?',
      [tenantId],
    );
    if (rows.isEmpty) return null;
    final tenant = rows.first;
    tenant['setup_complete'] = tenant['setup_complete'] == 1;
    return tenant;
  }

  static Future<void> saveBranches(
    String tenantId,
    List<BranchInputModel> branches,
  ) async {
    for (final branch in branches) {
      if (branch.id == null) continue;
      await LocalDatabase.execute(
        '''
        INSERT OR REPLACE INTO branches(
          id, tenant_id, name, address, city, is_active, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          branch.id,
          tenantId,
          branch.name,
          branch.address,
          branch.city,
          1,
          DateTime.now().toIso8601String(),
        ],
      );
    }
  }

  static Future<List<BranchInputModel>> loadBranches(String tenantId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM branches WHERE tenant_id = ? ORDER BY id',
      [tenantId],
    );
    return rows.map(BranchInputModel.fromMap).toList();
  }

  static Future<void> selectBranch({
    required String userId,
    required String branchId,
  }) async {
    await LocalDatabase.execute('UPDATE users SET branch_id = ? WHERE id = ?', [
      branchId,
      userId,
    ]);
  }

  static Future<void> saveProducts(
    String branchId,
    List<ProductModel> products,
  ) async {
    for (final product in products) {
      await upsertProduct(product);
    }
  }

  static Future<List<ProductModel>> loadProducts(String branchId) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT
        p.*,
        c.name AS category_name,
        c.default_reorder_threshold AS category_threshold,
        COALESCE(i.quantity, 0) AS stock,
        COALESCE(i.reorder_threshold, 0) AS branch_threshold
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      LEFT JOIN inventory i ON i.product_id = p.id AND i.branch_id = p.branch_id
      WHERE p.branch_id = ? AND COALESCE(p.is_active, 1) = 1
      ORDER BY p.name
      ''',
      [branchId],
    );
    return rows.map(_productFromRow).toList();
  }

  static Future<void> upsertProduct(ProductModel product) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO products(
        id, tenant_id, branch_id, category_id, name, sku, description,
        sale_price, cost_price, reorder_threshold, imei_tracked, is_active,
        created_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        product.id,
        product.tenantId,
        product.branchId,
        product.categoryId,
        product.name,
        product.sku,
        product.description,
        product.salePrice,
        product.costPrice,
        product.reorderThreshold,
        product.imeiTracked ? 1 : 0,
        product.isActive ? 1 : 0,
        DateTime.now().toIso8601String(),
      ],
    );
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO inventory(
        id, branch_id, product_id, quantity, reorder_threshold, updated_at
      ) VALUES(?, ?, ?, ?, ?, ?)
      ''',
      [
        product.id,
        product.branchId,
        product.id,
        product.stock,
        product.branchThreshold,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  static Future<void> deactivateProduct({
    required String branchId,
    required String productId,
  }) async {
    await LocalDatabase.execute(
      'UPDATE products SET is_active = 0 WHERE branch_id = ? AND id = ?',
      [branchId, productId],
    );
  }

  static Future<void> saveCategories(
    String branchId,
    List<CategoryModel> categories,
  ) async {
    await LocalDatabase.execute('DELETE FROM categories WHERE branch_id = ?', [
      branchId,
    ]);
    for (final category in categories) {
      await upsertCategory(category);
    }
  }

  static Future<List<CategoryModel>> loadCategories(String branchId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM categories WHERE branch_id = ? ORDER BY name',
      [branchId],
    );
    return rows.map(CategoryModel.fromMap).toList();
  }

  static Future<void> upsertCategory(CategoryModel category) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO categories(
        id, tenant_id, branch_id, name, default_reorder_threshold, created_at
      ) VALUES(?, ?, ?, ?, ?, ?)
      ''',
      [
        category.id,
        category.tenantId,
        category.branchId,
        category.name,
        category.defaultReorderThreshold,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  static Future<void> deleteCategory({
    required String branchId,
    required String categoryId,
  }) async {
    await LocalDatabase.execute(
      'DELETE FROM categories WHERE branch_id = ? AND id = ?',
      [branchId, categoryId],
    );
  }

  static ProductModel _productFromRow(Map<String, dynamic> row) {
    return ProductModel.fromMap({
      ...row,
      'imei_tracked': row['imei_tracked'] == 1,
      'is_active': row['is_active'] == 1,
      'sale_price': row['sale_price'] ?? 0,
      'cost_price': row['cost_price'] ?? 0,
      'stock': row['stock'] ?? 0,
    });
  }

  static Future<void> saveTenantSettings(Map<String, dynamic> settings) async {
    await LocalDatabase.execute(
      '''
    INSERT OR REPLACE INTO tenant_settings(
      tenant_id,
      adjustment_qty_threshold,
      adjustment_value_threshold,
      return_approval_threshold,
      return_window_days,
      cashier_discount_fixed_limit,
      cashier_discount_percent_limit,
      manager_discount_fixed_limit,
      manager_discount_percent_limit,
      discount_audit_threshold,
      receipt_footer,
      updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        settings['tenant_id'],
        settings['adjustment_qty_threshold'],
        settings['adjustment_value_threshold'],
        settings['return_approval_threshold'] ?? 25000,
        settings['return_window_days'] ?? 7,
        settings['cashier_discount_fixed_limit'] ?? 500,
        settings['cashier_discount_percent_limit'] ?? 10,
        settings['manager_discount_fixed_limit'] ?? 5000,
        settings['manager_discount_percent_limit'] ?? 25,
        settings['discount_audit_threshold'] ?? 1000,
        settings['receipt_footer'],
        settings['updated_at'],
      ],
    );
  }

  static Future<Map<String, dynamic>?> loadTenantSettings(
    String tenantId,
  ) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM tenant_settings WHERE tenant_id = ?',
      [tenantId],
    );

    return rows.isEmpty ? null : rows.first;
  }

  static Future<void> saveStockAdjustment(
    Map<String, dynamic> adjustment,
  ) async {
    await LocalDatabase.execute(
      '''
    INSERT OR REPLACE INTO stock_adjustments(
      id,
      tenant_id,
      branch_id,
      product_id,
      adjustment_type,
      quantity,
      reason,
      adjusted_by,
      created_at,
      user_id,
      reason_code,
      reason_note,
      is_override,
      unit_cost,
      total_value
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        adjustment['id'],
        adjustment['tenant_id'],
        adjustment['branch_id'],
        adjustment['product_id'],
        adjustment['adjustment_type'],
        adjustment['quantity'],
        adjustment['reason'],
        adjustment['adjusted_by'],
        adjustment['created_at'],
        adjustment['user_id'],
        adjustment['reason_code'],
        adjustment['reason_note'],
        adjustment['is_override'] == true ? 1 : 0,
        adjustment['unit_cost'],
        adjustment['total_value'],
      ],
    );
  }

  static Future<void> saveStockAdjustments(
    List<Map<String, dynamic>> adjustments,
  ) async {
    for (final adjustment in adjustments) {
      await saveStockAdjustment(adjustment);
    }
  }

  static Future<List<Map<String, dynamic>>> loadStockAdjustments(
    String branchId, {
    String? productId,
  }) async {
    if (productId == null) {
      return LocalDatabase.select(
        '''
      SELECT sa.*, p.name AS product_name
      FROM stock_adjustments sa
      LEFT JOIN products p ON p.id = sa.product_id
      WHERE sa.branch_id = ?
      ORDER BY sa.created_at DESC
      ''',
        [branchId],
      );
    }

    return LocalDatabase.select(
      '''
    SELECT sa.*, p.name AS product_name
    FROM stock_adjustments sa
    LEFT JOIN products p ON p.id = sa.product_id
    WHERE sa.branch_id = ?
      AND sa.product_id = ?
    ORDER BY sa.created_at DESC
    ''',
      [branchId, productId],
    );
  }

  // ════════════════════════════════════════
  // SALES
  // ════════════════════════════════════════

  static Future<void> saveSale(SaleModel sale) async {
    // Sale header
    await LocalDatabase.execute(
      '''
    INSERT OR REPLACE INTO sales(
      id, branch_id, customer_id, customer_name,
      user_id, status, subtotal, discount_amount,
      tax_amount, total, notes, void_reason,
      synced, created_at
    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
  ''',
      [
        sale.id,
        sale.branchId,
        sale.customerId,
        sale.customerName,
        sale.userId,
        sale.status.code,
        sale.subtotal,
        sale.discountAmount,
        sale.taxAmount,
        sale.total,
        sale.notes,
        sale.voidReason,
        0, // synced = false
        sale.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      ],
    );

    // Sale items
    for (final item in sale.items) {
      await LocalDatabase.execute(
        '''
      INSERT OR REPLACE INTO sale_items(
        id, sale_id, product_id, product_name,
        product_sku, quantity, unit_price,
        discount_amount, tax_rate, line_total
      ) VALUES(?,?,?,?,?,?,?,?,?,?)
    ''',
        [
          '${sale.id}_${item.productId}', // composite id
          sale.id,
          item.productId,
          item.productName,
          item.productSku,
          item.quantity,
          item.unitPrice,
          item.discountAmount,
          item.taxRate,
          item.lineTotal,
        ],
      );
    }

    // Sale payments
    for (final payment in sale.payments) {
      await LocalDatabase.execute(
        '''
      INSERT OR REPLACE INTO sale_payments(
        id, sale_id, method, amount
      ) VALUES(?,?,?,?)
    ''',
        [
          '${sale.id}_${payment.method.name}', // here we can have error
          sale.id,
          payment.method.name,
          payment.amount,
        ],
      );
    }
  }

  static Future<List<SaleModel>> loadSales(String branchId) async {
    // Sales fetch karo
    final salesRows = await LocalDatabase.select(
      '''
    SELECT * FROM sales
    WHERE branch_id = ?
    ORDER BY created_at DESC
    LIMIT 50
  ''',
      [branchId],
    );

    final sales = <SaleModel>[];

    for (final row in salesRows) {
      final saleId = row['id'] as String;

      // Items fetch
      final itemRows = await LocalDatabase.select(
        '''
      SELECT * FROM sale_items WHERE sale_id = ?
    ''',
        [saleId],
      );

      // Payments fetch
      final paymentRows = await LocalDatabase.select(
        '''
      SELECT * FROM sale_payments WHERE sale_id = ?
    ''',
        [saleId],
      );

      sales.add(
        SaleModel(
          id: saleId,
          branchId: row['branch_id'] as String,
          customerId: row['customer_id'] as String?,
          customerName: row['customer_name'] as String?,
          userId: row['user_id'] as String,
          status: SaleStatusX.fromCode(row['status'] as String),
          subtotal: (row['subtotal'] as num).toDouble(),
          discountAmount: (row['discount_amount'] as num).toDouble(),
          taxAmount: (row['tax_amount'] as num).toDouble(),
          total: (row['total'] as num).toDouble(),
          notes: row['notes'] as String?,
          voidReason: row['void_reason'] as String?,
          items:
              itemRows
                  .map(
                    (r) => CartItemModel(
                      productId: r['product_id'] as String,
                      productName: r['product_name'] as String,
                      productSku: r['product_sku'] as String?,
                      unitPrice: (r['unit_price'] as num).toDouble(),
                      quantity: (r['quantity'] as num).toInt(),
                      discountAmount: (r['discount_amount'] as num).toDouble(),
                      taxRate: (r['tax_rate'] as num).toDouble(),
                    ),
                  )
                  .toList(),
          payments:
              paymentRows
                  .map(
                    (r) => SalePaymentModel(
                      method: PaymentMethodX.fromCode(r['method'] as String),
                      amount: (r['amount'] as num).toDouble(),
                    ),
                  )
                  .toList(),
          createdAt:
              row['created_at'] != null
                  ? DateTime.parse(row['created_at'] as String)
                  : null,
        ),
      );
    }

    return sales;
  }

  static Future<void> markSaleSynced(String saleId) async {
    await LocalDatabase.execute('UPDATE sales SET synced = 1 WHERE id = ?', [
      saleId,
    ]);
  }

  static Future<List<Map<String, dynamic>>> loadUnsyncedSales(
    String branchId,
  ) async {
    return LocalDatabase.select(
      '''
    SELECT id FROM sales
    WHERE branch_id = ? AND synced = 0
    ORDER BY created_at ASC
  ''',
      [branchId],
    );
  }

  // ── Inventory local update (sale ke baad) ──
  static Future<void> decrementStock({
    required String branchId,
    required String productId,
    required int quantity,
  }) async {
    await LocalDatabase.execute(
      '''
    UPDATE inventory
    SET quantity = MAX(0, quantity - ?),
        updated_at = ?
    WHERE branch_id = ? AND product_id = ?
  ''',
      [quantity, DateTime.now().toIso8601String(), branchId, productId],
    );
  }

  static Future<void> incrementStock({
    required String branchId,
    required String productId,
    required int quantity,
  }) async {
    await LocalDatabase.execute(
      '''
    INSERT INTO inventory(
      id, branch_id, product_id, quantity, updated_at
    ) VALUES(?, ?, ?, ?, ?)
    ON CONFLICT(branch_id, product_id) DO UPDATE SET
      quantity = quantity + excluded.quantity,
      updated_at = excluded.updated_at
  ''',
      [
        '${branchId}_$productId',
        branchId,
        productId,
        quantity,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  // ════════════════════════════════════════
  // HELD CARTS (local)
  // ════════════════════════════════════════

  static Future<void> saveHeldCart(HeldCartModel cart) async {
    await LocalDatabase.execute(
      '''
    INSERT OR REPLACE INTO held_carts(
      id, branch_id, user_id, label,
      cart_data, created_at, expires_at
    ) VALUES(?,?,?,?,?,?,?)
  ''',
      [
        cart.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        cart.branchId,
        cart.userId,
        cart.label,
        jsonEncode(cart.toCartData()),
        cart.createdAt.toIso8601String(),
        cart.expiresAt?.toIso8601String(),
      ],
    );
  }

  static Future<List<HeldCartModel>> loadHeldCarts(String branchId) async {
    final rows = await LocalDatabase.select(
      '''
    SELECT * FROM held_carts
    WHERE branch_id = ?
    ORDER BY created_at DESC
  ''',
      [branchId],
    );

    return rows.map((row) {
      final cartData =
          jsonDecode(row['cart_data'] as String) as Map<String, dynamic>;
      final itemsList = cartData['items'] as List<dynamic>? ?? [];

      return HeldCartModel(
        id: row['id'] as String,
        branchId: row['branch_id'] as String,
        userId: row['user_id'] as String,
        label: row['label'] as String?,
        customerId: cartData['customer_id'] as String?,
        customerName: cartData['customer_name'] as String?,
        items:
            itemsList
                .map((e) => CartItemModel.fromMap(e as Map<String, dynamic>))
                .toList(),
        createdAt: DateTime.parse(row['created_at'] as String),
        expiresAt:
            row['expires_at'] != null
                ? DateTime.parse(row['expires_at'] as String)
                : null,
      );
    }).toList();
  }

  static Future<void> deleteHeldCart(String cartId) async {
    await LocalDatabase.execute('DELETE FROM held_carts WHERE id = ?', [
      cartId,
    ]);
  }

  // ════════════════════════════════════════
  // CUSTOMERS (local)
  // ════════════════════════════════════════

  static Future<void> saveCustomer(CustomerModel customer) async {
    await LocalDatabase.execute(
      '''
    INSERT OR REPLACE INTO customers(
      id, tenant_id, branch_id, full_name,
      phone, email, notes, credit_limit, outstanding_balance, created_at
    ) VALUES(?,?,?,?,?,?,?,?,?,?)
  ''',
      [
        customer.id,
        customer.tenantId,
        customer.branchId,
        customer.fullName,
        customer.phone,
        customer.email,
        customer.notes,
        customer.creditLimit,
        customer.outstandingBalance,
        customer.createdAt?.toIso8601String() ??
            DateTime.now().toIso8601String(),
      ],
    );
  }

  static Future<List<CustomerModel>> searchCustomers({
    required String branchId,
    required String query,
  }) async {
    final rows = await LocalDatabase.select(
      '''
    SELECT * FROM customers
    WHERE branch_id = ?
    AND (
      LOWER(full_name) LIKE ?
      OR phone LIKE ?
    )
    LIMIT 10
  ''',
      [branchId, '%${query.toLowerCase()}%', '%$query%'],
    );

    return rows
        .map(
          (row) => CustomerModel(
            id: row['id'] as String,
            tenantId: row['tenant_id'] as String,
            branchId: row['branch_id'] as String,
            fullName: row['full_name'] as String,
            phone: row['phone'] as String?,
            email: row['email'] as String?,
            notes: row['notes'] as String?,
            creditLimit: (row['credit_limit'] as num?)?.toDouble(),
            outstandingBalance:
                (row['outstanding_balance'] as num?)?.toDouble() ?? 0,
            createdAt:
                row['created_at'] != null
                    ? DateTime.parse(row['created_at'] as String)
                    : null,
          ),
        )
        .toList();
  }

  static Future<List<CustomerModel>> loadCustomers({
    required String branchId,
    String query = '',
    int limit = 100,
  }) async {
    final normalized = query.trim().toLowerCase();
    final rows = await LocalDatabase.select(
      '''
      SELECT * FROM customers
      WHERE branch_id = ?
      AND (
        ? = ''
        OR LOWER(full_name) LIKE ?
        OR phone LIKE ?
        OR LOWER(COALESCE(email, '')) LIKE ?
      )
      ORDER BY full_name
      LIMIT ?
      ''',
      [
        branchId,
        normalized,
        '%$normalized%',
        '%${query.trim()}%',
        '%$normalized%',
        limit,
      ],
    );

    return rows.map(_customerFromRow).toList();
  }

  static Future<CustomerModel?> loadCustomerById(String customerId) async {
    final rows = await LocalDatabase.select(
      'SELECT * FROM customers WHERE id = ?',
      [customerId],
    );
    return rows.isEmpty ? null : _customerFromRow(rows.first);
  }

  static Future<CustomerModel?> loadCustomerByPhone({
    required String tenantId,
    required String phone,
  }) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT * FROM customers
      WHERE tenant_id = ? AND phone = ?
      LIMIT 1
      ''',
      [tenantId, phone],
    );
    return rows.isEmpty ? null : _customerFromRow(rows.first);
  }

  static Future<void> updateCustomerCredit({
    required String customerId,
    double? creditLimit,
    bool clearCreditLimit = false,
    double? outstandingBalance,
  }) async {
    final customer = await loadCustomerById(customerId);
    if (customer == null) return;
    await saveCustomer(
      customer.copyWith(
        creditLimit: creditLimit,
        clearCreditLimit: clearCreditLimit,
        outstandingBalance: outstandingBalance,
      ),
    );
  }

  static Future<void> adjustCustomerOutstanding({
    required String customerId,
    required double delta,
  }) async {
    await LocalDatabase.execute(
      '''
      UPDATE customers
      SET outstanding_balance = MAX(0, outstanding_balance + ?)
      WHERE id = ?
      ''',
      [delta, customerId],
    );
  }

  static Future<void> saveCustomerSettlement(
    CustomerSettlementModel settlement, {
    bool synced = false,
  }) async {
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO customer_settlements(
        id, customer_id, branch_id, user_id, amount, method, notes, synced,
        created_at
      ) VALUES(?,?,?,?,?,?,?,?,?)
      ''',
      [
        settlement.id,
        settlement.customerId,
        settlement.branchId,
        settlement.userId,
        settlement.amount,
        settlement.method,
        settlement.notes,
        synced ? 1 : 0,
        settlement.createdAt.toIso8601String(),
      ],
    );
  }

  static Future<void> markCustomerSettlementSynced(String settlementId) async {
    await LocalDatabase.execute(
      'UPDATE customer_settlements SET synced = 1 WHERE id = ?',
      [settlementId],
    );
  }

  static Future<List<CustomerSettlementModel>> loadCustomerSettlements(
    String customerId,
  ) async {
    final rows = await LocalDatabase.select(
      '''
      SELECT * FROM customer_settlements
      WHERE customer_id = ?
      ORDER BY created_at DESC
      ''',
      [customerId],
    );
    return rows.map(CustomerSettlementModel.fromMap).toList();
  }

  static CustomerModel _customerFromRow(Map<String, dynamic> row) {
    return CustomerModel(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      branchId: row['branch_id'] as String,
      fullName: row['full_name'] as String,
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      notes: row['notes'] as String?,
      creditLimit: (row['credit_limit'] as num?)?.toDouble(),
      outstandingBalance: (row['outstanding_balance'] as num?)?.toDouble() ?? 0,
      createdAt:
          row['created_at'] != null
              ? DateTime.parse(row['created_at'] as String)
              : null,
    );
  }

  // ════════════════════════════════════════
  // REPAIR MODULE - LOCAL SQLITE METHODS
  // ════════════════════════════════════════
  //
  // Important:
  // LocalDatabase sirf SQL execute/select karta hai.
  // LocalStore app ko clean functions deta hai:
  //
  // saveRepairTicket()
  // loadRepairTickets()
  // saveRepairStatusLog()
  // markInventoryUnitInRepair()
  //
  // Isse RepairRepository clean rahegi.

  static Future<void> saveRepairTicket(RepairTicketModel ticket) async {
    // Yeh method repair ticket ko local SQLite mein save karta hai.
    //
    // INSERT OR REPLACE ka matlab:
    // - agar id pehle se nahi hai -> insert
    // - agar id already hai -> replace/update
    //
    // Offline mode mein ticket pehle local save hoga,
    // phir mutation queue se Supabase sync hoga.
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO repair_tickets(
        id,
        tenant_id,
        branch_id,
        ticket_no,
        customer_id,
        customer_name,
        customer_phone,
        product_id,
        inventory_unit_id,
        device_brand,
        device_model,
        device_color,
        imei,
        fault_description,
        technician_id,
        status,
        estimated_cost,
        estimated_completion_at,
        estimate_note,
        parts_cost,
        labor_cost,
        total_cost,
        warranty_reference,
        warranty_note,
        is_warranty_repair,
        created_by,
        completed_at,
        delivered_at,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        ticket.id,
        ticket.tenantId,
        ticket.branchId,
        ticket.ticketNo,
        ticket.customerId,
        ticket.customerName,
        ticket.customerPhone,
        ticket.productId,
        ticket.inventoryUnitId,
        ticket.deviceBrand,
        ticket.deviceModel,
        ticket.deviceColor,
        ticket.imei,
        ticket.faultDescription,
        ticket.technicianId,
        ticket.status.code,
        ticket.estimatedCost,
        ticket.estimatedCompletionAt?.toIso8601String(),
        ticket.estimateNote,
        ticket.partsCost,
        ticket.laborCost,
        ticket.totalCost,
        ticket.warrantyReference,
        ticket.warrantyNote,
        ticket.isWarrantyRepair ? 1 : 0,
        ticket.createdBy,
        ticket.completedAt?.toIso8601String(),
        ticket.deliveredAt?.toIso8601String(),
        ticket.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        ticket.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      ],
    );
  }

  static Future<List<RepairTicketModel>> loadRepairTickets(
    String branchId, {
    RepairTicketStatus? status,
    int limit = 100,
  }) async {
    // Branch ke repair tickets load karta hai.
    //
    // Agar status null hai:
    //   saare tickets
    //
    // Agar status given hai:
    //   sirf us status ke tickets
    //
    // Example:
    // loadRepairTickets(branchId, status: RepairTicketStatus.received)
    if (status == null) {
      final rows = await LocalDatabase.select(
        '''
        SELECT *
        FROM repair_tickets
        WHERE branch_id = ?
        ORDER BY created_at DESC
        LIMIT ?
        ''',
        [branchId, limit],
      );

      return rows.map(RepairTicketModel.fromMap).toList();
    }

    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM repair_tickets
      WHERE branch_id = ?
        AND status = ?
      ORDER BY created_at DESC
      LIMIT ?
      ''',
      [branchId, status.code, limit],
    );

    return rows.map(RepairTicketModel.fromMap).toList();
  }

  static Future<RepairTicketModel?> loadRepairTicketById(
    String ticketId,
  ) async {
    // Specific ticket detail screen ke liye.
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM repair_tickets
      WHERE id = ?
      LIMIT 1
      ''',
      [ticketId],
    );

    return rows.isEmpty ? null : RepairTicketModel.fromMap(rows.first);
  }

  static Future<void> saveRepairStatusLog(RepairStatusLogModel log) async {
    // Har status change ka audit log local SQLite mein save hota hai.
    //
    // Example:
    // old_status = received
    // new_status = diagnosed
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO repair_status_logs(
        id,
        ticket_id,
        tenant_id,
        branch_id,
        old_status,
        new_status,
        changed_by,
        note,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        log.id,
        log.ticketId,
        log.tenantId,
        log.branchId,
        log.oldStatus?.code,
        log.newStatus.code,
        log.changedBy,
        log.note,
        log.createdAt.toIso8601String(),
      ],
    );
  }

  static Future<List<RepairStatusLogModel>> loadRepairStatusLogs(
    String ticketId,
  ) async {
    // Ticket ki full timeline/history load karta hai.
    //
    // UI mein:
    // Received -> Diagnosed -> In Progress ...
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM repair_status_logs
      WHERE ticket_id = ?
      ORDER BY created_at DESC
      ''',
      [ticketId],
    );

    return rows.map(RepairStatusLogModel.fromMap).toList();
  }

  static Future<void> upsertInventoryUnit(InventoryUnitModel unit) async {
    // IMEI/unit ko local DB mein save/update karta hai.
    //
    // Repair create hote waqt agar IMEI diya gaya hai,
    // to local inventory unit ka status "in_repair" save hoga.
    await LocalDatabase.execute(
      '''
      INSERT OR REPLACE INTO inventory_units(
        id,
        tenant_id,
        branch_id,
        product_id,
        imei,
        status,
        sale_id,
        customer_id,
        warranty_start_at,
        warranty_end_at,
        current_repair_ticket_id,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        unit.id,
        unit.tenantId,
        unit.branchId,
        unit.productId,
        unit.imei,
        unit.status.code,
        unit.saleId,
        unit.customerId,
        unit.warrantyStartAt?.toIso8601String(),
        unit.warrantyEndAt?.toIso8601String(),
        unit.currentRepairTicketId,
        unit.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        unit.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      ],
    );
  }

  static Future<InventoryUnitModel?> loadInventoryUnitByImei({
    required String branchId,
    required String imei,
  }) async {
    // IMEI se local unit find karta hai.
    //
    // Use case:
    // customer IMEI deta hai -> app check karegi ke yeh unit pehle se known hai ya nahi.
    final rows = await LocalDatabase.select(
      '''
      SELECT *
      FROM inventory_units
      WHERE branch_id = ?
        AND imei = ?
      LIMIT 1
      ''',
      [branchId, imei],
    );

    return rows.isEmpty ? null : InventoryUnitModel.fromMap(rows.first);
  }

  static Future<void> markInventoryUnitInRepair({
    required String branchId,
    required String imei,
    required String ticketId,
  }) async {
    // Agar IMEI unit local DB mein already exist karti hai,
    // to uska status in_repair kar do.
    //
    // Agar unit exist nahi karti, repository later new unit create karegi.
    await LocalDatabase.execute(
      '''
      UPDATE inventory_units
      SET status = ?,
          current_repair_ticket_id = ?,
          updated_at = ?
      WHERE branch_id = ?
        AND imei = ?
      ''',
      [
        InventoryUnitStatus.inRepair.code,
        ticketId,
        DateTime.now().toIso8601String(),
        branchId,
        imei,
      ],
    );
  }

  static Future<void> saveRepairTicketWithInitialLog({
    required RepairTicketModel ticket,
    required RepairStatusLogModel log,
    InventoryUnitModel? inventoryUnit,
  }) async {
    // Yeh helper create ticket flow ke liye hai.
    //
    // Create repair ticket mein 3 local actions ek saath hoti hain:
    // 1. ticket save
    // 2. initial status log save
    // 3. optional IMEI unit save/update
    //
    // Isse repository mein code clean rahega.
    await saveRepairTicket(ticket);
    await saveRepairStatusLog(log);

    if (inventoryUnit != null) {
      await upsertInventoryUnit(inventoryUnit);
    } else if (ticket.imei != null && ticket.imei!.trim().isNotEmpty) {
      await markInventoryUnitInRepair(
        branchId: ticket.branchId,
        imei: ticket.imei!.trim(),
        ticketId: ticket.id,
      );
    }
  }
}
