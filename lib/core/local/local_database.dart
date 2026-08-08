import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LocalDatabase {
  LocalDatabase._();

  static final RegExp _identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static const Set<String> managedTables = {
    'users',
    'tenants',
    'branches',
    'categories',
    'products',
    'inventory',
    'stock_adjustments',
    'tenant_settings',
    'customers',
    'customer_id_aliases',
    'sales',
    'sale_items',
    'sale_payments',
    'customer_settlements',
    'customer_ledger_entries',
    'sale_returns',
    'sale_return_items',
    'sale_return_refund_legs',
    'sale_return_credit_adjustments',
    'discount_audit_logs',
    'receipt_delivery_logs',
    'held_carts',
    'inventory_units',
    'repair_tickets',
    'repair_status_logs',
    'repair_payments',
    'repair_parts',
    'repair_part_returns',
    'repair_financial_events',
    'suppliers',
    'inventory_supplier_options',
    'supplier_products',
    'purchase_orders',
    'purchase_order_items',
    'goods_receipts',
    'goods_receipt_items',
    'supplier_payments',
    'supplier_ledger_entries',
    'accounts',
    'account_transactions',
    'mobile_service_providers',
    'mobile_service_charge_rules',
    'mobile_service_transactions',
    'business_report_schedules',
    'business_report_delivery_jobs',
    'business_report_cache',
  };

  static const List<String> _deleteOrder = [
    'mobile_service_transactions',
    'mobile_service_charge_rules',
    'mobile_service_providers',
    'account_transactions',
    'accounts',
    'business_report_cache',
    'business_report_delivery_jobs',
    'business_report_schedules',
    'goods_receipt_items',
    'goods_receipts',
    'supplier_payments',
    'supplier_ledger_entries',
    'purchase_order_items',
    'purchase_orders',
    'supplier_products',
    'inventory_supplier_options',
    'suppliers',
    'repair_status_logs',
    'repair_payments',
    'repair_financial_events',
    'repair_part_returns',
    'repair_parts',
    'repair_tickets',
    'inventory_units',
    'receipt_delivery_logs',
    'discount_audit_logs',
    'sale_return_items',
    'sale_return_refund_legs',
    'sale_return_credit_adjustments',
    'sale_returns',
    'customer_settlements',
    'customer_ledger_entries',
    'customer_id_aliases',
    'sale_payments',
    'sale_items',
    'sales',
    'held_carts',
    'stock_adjustments',
    'inventory',
    'products',
    'categories',
    'tenant_settings',
    'customers',
    'branches',
    'tenants',
    'users',
  ];

  static final QueryExecutor _executor = LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(path.join(directory.path, 'mobileshop_saas.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
  static final GeneratedDatabase _db = _RawLocalDatabase(_executor);
  static Future<void>? _initialization;

  static Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    await _db.customStatement('PRAGMA foreign_keys = ON');
    await _createTables();
  }

  static Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?> variables = const [],
  ]) async {
    await initialize();
    final rows =
        await _db
            .customSelect(sql, variables: variables.map(Variable.new).toList())
            .get();
    return rows.map((row) => row.data).toList();
  }

  static Future<void> execute(
    String sql, [
    List<Object?> variables = const [],
  ]) async {
    await initialize();
    await _db.customStatement(sql, variables);
  }

  static Future<T> runInTransaction<T>(Future<T> Function() action) async {
    await initialize();
    return _db.transaction(action);
  }

  static Future<void> deleteRows({
    required String table,
    required String whereColumn,
    required Object? equals,
  }) async {
    await initialize();
    _requireManagedTable(table);
    _requireSafeIdentifier(whereColumn);
    await _db.customStatement('DELETE FROM $table WHERE $whereColumn = ?', [
      equals,
    ]);
  }

  static Future<void> deleteRowById({
    required String table,
    required Object? id,
    String idColumn = 'id',
  }) {
    return deleteRows(table: table, whereColumn: idColumn, equals: id);
  }

  static Future<void> clearTable(String table) async {
    await initialize();
    _requireManagedTable(table);
    await _db.customStatement('DELETE FROM $table');
  }

  static Future<void> clearAllTables({Set<String> except = const {}}) async {
    await initialize();
    for (final table in except) {
      _requireManagedTable(table);
    }
    await _db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      for (final table in _deleteOrder) {
        if (!except.contains(table)) {
          await _db.customStatement('DELETE FROM $table');
        }
      }
    } finally {
      await _db.customStatement('PRAGMA foreign_keys = ON');
    }
  }

  static Future<void> dropTable(String table, {bool recreate = true}) async {
    await initialize();
    _requireManagedTable(table);
    await _db.customStatement('DROP TABLE IF EXISTS $table');
    if (recreate) {
      _initialization = null;
      await initialize();
    }
  }

  static void _requireManagedTable(String table) {
    _requireSafeIdentifier(table);
    if (!managedTables.contains(table)) {
      throw ArgumentError.value(
        table,
        'table',
        'Table is not managed locally.',
      );
    }
  }

  static void _requireSafeIdentifier(String identifier) {
    if (!_identifierPattern.hasMatch(identifier)) {
      throw ArgumentError.value(identifier, 'identifier', 'Unsafe identifier.');
    }
  }

  static Future<void> _createTables() async {
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        branch_id TEXT,
        full_name TEXT,
        email TEXT,
        phone TEXT,
        role TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS tenants (
        id TEXT PRIMARY KEY,
        shop_name TEXT NOT NULL,
        business_type TEXT NOT NULL,
        branch_count INTEGER NOT NULL DEFAULT 1,
        plan TEXT NOT NULL DEFAULT 'starter',
        status TEXT NOT NULL DEFAULT 'active',
        setup_complete INTEGER NOT NULL DEFAULT 0,
        created_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS branches (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        name TEXT NOT NULL,
        address TEXT NOT NULL,
        city TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        default_reorder_threshold INTEGER NOT NULL DEFAULT 5,
        created_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        category_id TEXT,
        name TEXT NOT NULL,
        sku TEXT,
        barcode TEXT,
        description TEXT,
        sale_price REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        reorder_threshold INTEGER NOT NULL DEFAULT 0,
        imei_tracked INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await _addColumnIfMissing(
      table: 'categories',
      column: 'default_reorder_threshold',
      definition: 'INTEGER NOT NULL DEFAULT 5',
    );
    await _addColumnIfMissing(
      table: 'products',
      column: 'barcode',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'products',
      column: 'reorder_threshold',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      table: 'products',
      column: 'updated_at',
      definition: 'TEXT',
    );

    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_products_branch_barcode_unique
      ON products(branch_id, barcode COLLATE NOCASE)
      WHERE barcode IS NOT NULL AND trim(barcode) <> ''
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS inventory (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        product_id TEXT,
        quantity INTEGER NOT NULL DEFAULT 0,
        reorder_threshold INTEGER NOT NULL DEFAULT 5,
        updated_at TEXT,
        UNIQUE(branch_id, product_id)
      )
    ''');

    await _db.customStatement('''   
      CREATE TABLE IF NOT EXISTS stock_adjustments (
          id TEXT PRIMARY KEY,
          tenant_id TEXT NOT NULL,
          branch_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          adjustment_type TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          reason TEXT NOT NULL,
          adjusted_by TEXT NOT NULL,
          created_at TEXT,
          user_id TEXT NOT NULL,
          reason_code TEXT NOT NULL,
          reason_note TEXT,
          is_override INTEGER NOT NULL DEFAULT 0,
          unit_cost REAL,
          total_value REAL
        )
    ''');
    await _db.customStatement('''   
      CREATE TABLE IF NOT EXISTS tenant_settings (
          tenant_id TEXT PRIMARY KEY,
          adjustment_qty_threshold INTEGER NOT NULL DEFAULT 10,
          adjustment_value_threshold REAL NOT NULL DEFAULT 50000,
          return_approval_threshold REAL NOT NULL DEFAULT 25000,
          return_window_days INTEGER NOT NULL DEFAULT 7,
          cashier_discount_fixed_limit REAL NOT NULL DEFAULT 500,
          cashier_discount_percent_limit REAL NOT NULL DEFAULT 10,
          manager_discount_fixed_limit REAL NOT NULL DEFAULT 5000,
          manager_discount_percent_limit REAL NOT NULL DEFAULT 25,
          discount_audit_threshold REAL NOT NULL DEFAULT 1000,
          receipt_footer TEXT,
          updated_at TEXT
        )
    ''');
    await _addColumnIfMissing(
      table: 'tenant_settings',
      column: 'return_approval_threshold',
      definition: 'REAL NOT NULL DEFAULT 25000',
    );
    await _addColumnIfMissing(
      table: 'tenant_settings',
      column: 'return_window_days',
      definition: 'INTEGER NOT NULL DEFAULT 7',
    );
    await _addColumnIfMissing(
      table: 'tenant_settings',
      column: 'cashier_discount_fixed_limit',
      definition: 'REAL NOT NULL DEFAULT 500',
    );
    await _addColumnIfMissing(
      table: 'tenant_settings',
      column: 'cashier_discount_percent_limit',
      definition: 'REAL NOT NULL DEFAULT 10',
    );
    await _addColumnIfMissing(
      table: 'tenant_settings',
      column: 'manager_discount_fixed_limit',
      definition: 'REAL NOT NULL DEFAULT 5000',
    );
    await _addColumnIfMissing(
      table: 'tenant_settings',
      column: 'manager_discount_percent_limit',
      definition: 'REAL NOT NULL DEFAULT 25',
    );
    await _addColumnIfMissing(
      table: 'tenant_settings',
      column: 'discount_audit_threshold',
      definition: 'REAL NOT NULL DEFAULT 1000',
    );
    await _addColumnIfMissing(
      table: 'tenant_settings',
      column: 'receipt_footer',
      definition: 'TEXT',
    );

    // _createTables() mein yeh add karo:

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS customers (
      id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      branch_id TEXT NOT NULL,
      full_name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      notes TEXT,
      credit_limit REAL,
      outstanding_balance REAL NOT NULL DEFAULT 0,
      created_at TEXT
    )
  ''');
    await _addColumnIfMissing(
      table: 'customers',
      column: 'credit_limit',
      definition: 'REAL',
    );
    await _addColumnIfMissing(
      table: 'customers',
      column: 'outstanding_balance',
      definition: 'REAL NOT NULL DEFAULT 0',
    );

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS sales (
      id TEXT PRIMARY KEY,
      branch_id TEXT NOT NULL,
      customer_id TEXT,
      customer_name TEXT,
      user_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'completed',
      subtotal REAL NOT NULL DEFAULT 0,
      discount_amount REAL NOT NULL DEFAULT 0,
      tax_amount REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      notes TEXT,
      void_reason TEXT,
      synced INTEGER NOT NULL DEFAULT 0,
      created_at TEXT
    )
  ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT,
        item_resolution TEXT NOT NULL DEFAULT 'existing_product',
        item_name TEXT,
        product_name TEXT NOT NULL,
        product_sku TEXT,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        unit_cost_at_sale REAL,
        discount_amount REAL NOT NULL DEFAULT 0,
        tax_rate REAL NOT NULL DEFAULT 0,
        cogs_total REAL,
        line_total REAL NOT NULL
      )
  ''');
    await _addColumnIfMissing(
      table: 'sale_items',
      column: 'unit_cost_at_sale',
      definition: 'REAL',
    );
    await _addColumnIfMissing(
      table: 'sale_items',
      column: 'cogs_total',
      definition: 'REAL',
    );

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS sale_payments (
      id TEXT PRIMARY KEY,
      sale_id TEXT NOT NULL,
      method TEXT NOT NULL,
      amount REAL NOT NULL,
      account_id TEXT,
      ledger_transaction_id TEXT
    )
  ''');
    await _addColumnIfMissing(
      table: 'sale_payments',
      column: 'account_id',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'sale_payments',
      column: 'ledger_transaction_id',
      definition: 'TEXT',
    );
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_sale_payments_account
      ON sale_payments(account_id)
      WHERE account_id IS NOT NULL
    ''');
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_sale_payments_ledger_transaction
      ON sale_payments(ledger_transaction_id)
      WHERE ledger_transaction_id IS NOT NULL
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS customer_id_aliases (
        local_id TEXT PRIMARY KEY,
        remote_id TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS customer_settlements (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      branch_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      amount REAL NOT NULL,
      method TEXT NOT NULL,
      account_id TEXT,
      ledger_transaction_id TEXT,
      notes TEXT,
      synced INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS customer_ledger_entries (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        entry_type TEXT NOT NULL CHECK(entry_type IN ('charge', 'credit')),
        amount REAL NOT NULL CHECK(amount > 0),
        reason TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_customer_ledger_entries_customer
      ON customer_ledger_entries(customer_id, created_at)
    ''');
    await _addColumnIfMissing(
      table: 'customer_settlements',
      column: 'account_id',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'customer_settlements',
      column: 'ledger_transaction_id',
      definition: 'TEXT',
    );
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_settlement_ledger
      ON customer_settlements(ledger_transaction_id)
      WHERE ledger_transaction_id IS NOT NULL
    ''');

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS sale_returns (
      id TEXT PRIMARY KEY,
      original_sale_id TEXT NOT NULL,
      branch_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      status TEXT NOT NULL,
      refund_method TEXT NOT NULL,
      refund_amount REAL NOT NULL DEFAULT 0,
      approval_required_reason TEXT,
      override_reason TEXT,
      approved_by TEXT,
      synced INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS sale_return_items (
      id TEXT PRIMARY KEY,
      return_id TEXT NOT NULL,
      original_sale_id TEXT NOT NULL,
      product_id TEXT NOT NULL,
      product_name TEXT NOT NULL,
      product_sku TEXT,
      quantity INTEGER NOT NULL,
      refund_amount REAL NOT NULL DEFAULT 0,
      restock_product_id TEXT,
      restock_condition TEXT NOT NULL DEFAULT 'returned',
      resale_price REAL
    )
  ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS sale_return_refund_legs (
      id TEXT PRIMARY KEY,
      return_id TEXT NOT NULL,
      original_payment_id TEXT NOT NULL,
      account_id TEXT NOT NULL,
      amount REAL NOT NULL,
      ledger_transaction_id TEXT NOT NULL
    )
  ''');
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_return_refund_payment
      ON sale_return_refund_legs(return_id, original_payment_id)
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS sale_return_credit_adjustments (
        id TEXT PRIMARY KEY,
        return_id TEXT NOT NULL UNIQUE,
        original_sale_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_return_refund_ledger
      ON sale_return_refund_legs(ledger_transaction_id)
    ''');
    await _addColumnIfMissing(
      table: 'sale_return_items',
      column: 'restock_product_id',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'sale_return_items',
      column: 'restock_condition',
      definition: "TEXT NOT NULL DEFAULT 'returned'",
    );
    await _addColumnIfMissing(
      table: 'sale_return_items',
      column: 'resale_price',
      definition: 'REAL',
    );

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS discount_audit_logs (
      id TEXT PRIMARY KEY,
      sale_id TEXT,
      branch_id TEXT NOT NULL,
      cashier_id TEXT NOT NULL,
      approved_by TEXT,
      scope TEXT NOT NULL,
      product_id TEXT,
      discount_type TEXT NOT NULL,
      requested_value REAL NOT NULL,
      discount_amount REAL NOT NULL,
      reason TEXT,
      synced INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS receipt_delivery_logs (
      id TEXT PRIMARY KEY,
      sale_id TEXT NOT NULL,
      delivery_method TEXT NOT NULL,
      recipient TEXT,
      duplicate INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS held_carts (
      id TEXT PRIMARY KEY,
      branch_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      label TEXT,
      cart_data TEXT NOT NULL,
      created_at TEXT,
      expires_at TEXT
    )
  ''');
    // ════════════════════════════════════════
    // INVENTORY UNITS / IMEI UNITS
    // ════════════════════════════════════════
    //
    // Yeh table aik physical mobile/device ko represent karti hai.
    // Product table sirf "Samsung A15" batata hai.
    // inventory_units table us Samsung A15 ke exact IMEI piece ko track karti hai.
    //
    // Repair module mein ticket create hote hi IMEI unit ka status "in_repair"
    // local DB mein bhi update hoga.
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS inventory_units (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        imei TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'available',
        sale_id TEXT,
        customer_id TEXT,
        warranty_start_at TEXT,
        warranty_end_at TEXT,
        current_repair_ticket_id TEXT,
        created_at TEXT,
        updated_at TEXT,
        UNIQUE(branch_id, imei)
      )
    ''');

    // ════════════════════════════════════════
    // REPAIR TICKETS
    // ════════════════════════════════════════
    //
    // Yeh main repair job/order table hai.
    // Customer ne device chhori, issue bataya, technician assign hua,
    // estimate diya gaya — sab yahan save hoga.
    //
    // Offline mode mein bhi ticket yahin save hoga.
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS repair_tickets (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        ticket_no TEXT,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        product_id TEXT,
        inventory_unit_id TEXT,
        device_brand TEXT NOT NULL,
        device_model TEXT NOT NULL,
        device_color TEXT,
        imei TEXT,
        fault_description TEXT NOT NULL,
        technician_id TEXT,
        status TEXT NOT NULL DEFAULT 'received',
        estimated_cost REAL,
        estimated_completion_at TEXT,
        estimate_note TEXT,
        parts_cost REAL,
        labor_cost REAL,
        total_cost REAL,
        warranty_reference TEXT,
        warranty_note TEXT,
        is_warranty_repair INTEGER NOT NULL DEFAULT 0,
        created_by TEXT NOT NULL,
        completed_at TEXT,
        delivered_at TEXT,
        created_at TEXT,
        updated_at TEXT,
        customer_charge REAL,
        service_charge REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        per_job_commission REAL NOT NULL DEFAULT 0,
        other_direct_cost REAL NOT NULL DEFAULT 0,
        finalized_at TEXT,
        reversed_at TEXT,
        archived_at TEXT,
        archived_by TEXT,
        UNIQUE(branch_id, ticket_no)
      )
    ''');
    for (final column in const <(String, String)>[
      ('customer_charge', 'REAL'),
      ('service_charge', 'REAL NOT NULL DEFAULT 0'),
      ('discount_amount', 'REAL NOT NULL DEFAULT 0'),
      ('per_job_commission', 'REAL NOT NULL DEFAULT 0'),
      ('other_direct_cost', 'REAL NOT NULL DEFAULT 0'),
      ('finalized_at', 'TEXT'),
      ('reversed_at', 'TEXT'),
      ('archived_at', 'TEXT'),
      ('archived_by', 'TEXT'),
    ]) {
      await _addColumnIfMissing(
        table: 'repair_tickets',
        column: column.$1,
        definition: column.$2,
      );
    }

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS repair_parts (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        ticket_id TEXT NOT NULL,
        source_type TEXT NOT NULL,
        product_id TEXT,
        supplier_id TEXT,
        settlement_type TEXT NOT NULL DEFAULT 'already_recorded',
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost_snapshot REAL NOT NULL,
        unit_sale_price REAL NOT NULL,
        state TEXT NOT NULL DEFAULT 'planned',
        consumed_at TEXT,
        reversed_at TEXT,
        created_by TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await _addColumnIfMissing(
      table: 'repair_parts',
      column: 'settlement_type',
      definition: "TEXT NOT NULL DEFAULT 'already_recorded'",
    );
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS repair_part_returns (
        part_id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        ticket_id TEXT NOT NULL,
        reversal_event_id TEXT NOT NULL,
        source_type TEXT NOT NULL,
        product_id TEXT,
        supplier_id TEXT,
        settlement_type TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost_snapshot REAL NOT NULL,
        unit_sale_price_snapshot REAL NOT NULL,
        returned_by TEXT NOT NULL,
        returned_at TEXT NOT NULL,
        UNIQUE(ticket_id, part_id)
      )
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS repair_financial_events (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        ticket_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        source_event_key TEXT NOT NULL,
        revenue_amount REAL NOT NULL,
        inventory_cost REAL NOT NULL,
        direct_parts_cost REAL NOT NULL,
        commission_cost REAL NOT NULL,
        other_direct_cost REAL NOT NULL,
        gross_profit REAL NOT NULL,
        reversal_of_event_id TEXT,
        occurred_at TEXT NOT NULL,
        effective_at TEXT NOT NULL,
        created_by TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(tenant_id, branch_id, source_event_key)
      )
    ''');
    await _addColumnIfMissing(
      table: 'repair_financial_events',
      column: 'effective_at',
      definition: 'TEXT',
    );
    await _db.customStatement('''
      UPDATE repair_financial_events
      SET effective_at = COALESCE(
        (
          SELECT original.effective_at
          FROM repair_financial_events original
          WHERE original.id = repair_financial_events.reversal_of_event_id
        ),
        occurred_at
      )
      WHERE effective_at IS NULL OR effective_at = ''
    ''');

    // ════════════════════════════════════════
    // REPAIR STATUS LOGS
    // ════════════════════════════════════════
    //
    // Har status change ka permanent local audit trail.
    // Example:
    // null -> received
    // received -> diagnosed
    // diagnosed -> in_progress
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS repair_status_logs (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        old_status TEXT,
        new_status TEXT NOT NULL,
        changed_by TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS repair_payments (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        ticket_id TEXT NOT NULL,
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        account_id TEXT NOT NULL,
        ledger_transaction_id TEXT NOT NULL,
        note TEXT,
        received_by TEXT NOT NULL,
        received_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_repair_payment_ledger
      ON repair_payments(ledger_transaction_id)
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS repair_payment_refunds (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL UNIQUE,
        account_id TEXT NOT NULL,
        amount REAL NOT NULL,
        ledger_transaction_id TEXT NOT NULL UNIQUE,
        refunded_by TEXT NOT NULL,
        refunded_at TEXT NOT NULL
      )
    ''');

    // ════════════════════════════════════════
    // SUPPLIER TABLES + INDEXES
    // ════════════════════════════════════════
    //
    // Supplier/procurement local tables.
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT,
        name TEXT NOT NULL,
        contact_person TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        city TEXT,
        payment_terms TEXT,
        outstanding_balance REAL NOT NULL DEFAULT 0,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_by TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS inventory_supplier_options (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT
      )
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS supplier_products (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        supplier_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        supplier_sku TEXT,
        last_cost REAL,
        created_at TEXT,
        UNIQUE(supplier_id, product_id)
      )
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_inventory_supplier_options_branch_name
      ON inventory_supplier_options(branch_id, name)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_supplier_products_supplier_product
      ON supplier_products(supplier_id, product_id)
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        supplier_id TEXT NOT NULL,
        po_no TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        expected_delivery_at TEXT,
        notes TEXT,
        total_expected_cost REAL NOT NULL DEFAULT 0,
        total_received_cost REAL NOT NULL DEFAULT 0,
        created_by TEXT,
        sent_at TEXT,
        cancelled_at TEXT,
        created_at TEXT,
        updated_at TEXT,
        UNIQUE(branch_id, po_no)
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS purchase_order_items (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        purchase_order_id TEXT NOT NULL,
        product_id TEXT,
        product_resolution TEXT NOT NULL DEFAULT 'existing_product',
        product_draft_json TEXT,
        resolved_product_id TEXT,
        product_name TEXT NOT NULL,
        product_sku TEXT,
        ordered_quantity INTEGER NOT NULL,
        received_quantity INTEGER NOT NULL DEFAULT 0,
        negotiated_unit_cost REAL NOT NULL DEFAULT 0,
        actual_unit_cost REAL,
        line_total REAL NOT NULL DEFAULT 0,
        created_at TEXT
      )
    ''');
    await _addColumnIfMissing(
      table: 'purchase_order_items',
      column: 'product_resolution',
      definition: "TEXT NOT NULL DEFAULT 'existing_product'",
    );
    await _addColumnIfMissing(
      table: 'purchase_order_items',
      column: 'product_draft_json',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'purchase_order_items',
      column: 'resolved_product_id',
      definition: 'TEXT',
    );

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS goods_receipts (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        purchase_order_id TEXT NOT NULL,
        supplier_id TEXT NOT NULL,
        receipt_no TEXT NOT NULL,
        note TEXT,
        total_received_value REAL NOT NULL DEFAULT 0,
        received_by TEXT,
        received_at TEXT,
        UNIQUE(branch_id, receipt_no)
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS goods_receipt_items (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        goods_receipt_id TEXT NOT NULL,
        purchase_order_id TEXT NOT NULL,
        purchase_order_item_id TEXT NOT NULL,
        product_id TEXT,
        item_resolution TEXT NOT NULL DEFAULT 'existing_product',
        item_name TEXT,
        received_quantity INTEGER NOT NULL,
        actual_unit_cost REAL NOT NULL DEFAULT 0,
        update_product_cost INTEGER NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        created_at TEXT
      )
    ''');
    await _addColumnIfMissing(
      table: 'goods_receipt_items',
      column: 'item_resolution',
      definition: "TEXT NOT NULL DEFAULT 'existing_product'",
    );
    await _addColumnIfMissing(
      table: 'goods_receipt_items',
      column: 'item_name',
      definition: 'TEXT',
    );
    await _makeProcurementProductLinksNullable();

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        supplier_id TEXT NOT NULL,
        purchase_order_id TEXT,
        amount REAL NOT NULL,
        method TEXT,
        account_id TEXT,
        ledger_transaction_id TEXT,
        note TEXT,
        paid_by TEXT,
        paid_at TEXT,
        created_at TEXT
      )
    ''');
    await _addColumnIfMissing(
      table: 'supplier_payments',
      column: 'purchase_order_id',
      definition: 'TEXT',
    );
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS supplier_ledger_entries (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        supplier_id TEXT NOT NULL,
        entry_type TEXT NOT NULL,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        source_event_key TEXT NOT NULL,
        reference_type TEXT NOT NULL,
        reference_id TEXT NOT NULL,
        description TEXT,
        occurred_at TEXT NOT NULL,
        created_by TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_ledger_source
      ON supplier_ledger_entries(tenant_id, branch_id, source_event_key)
    ''');
    await _addColumnIfMissing(
      table: 'supplier_payments',
      column: 'account_id',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'supplier_payments',
      column: 'ledger_transaction_id',
      definition: 'TEXT',
    );
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_payment_ledger
      ON supplier_payments(ledger_transaction_id)
      WHERE ledger_transaction_id IS NOT NULL
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        account_type TEXT NOT NULL DEFAULT 'cash',
        opening_balance REAL NOT NULL DEFAULT 0,
        current_balance REAL NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        note TEXT,
        created_by TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS account_transactions (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        related_account_id TEXT,
        transfer_group_id TEXT,
        transaction_type TEXT NOT NULL,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        reference_type TEXT,
        reference_id TEXT,
        source_event_key TEXT,
        reversal_of_transaction_id TEXT,
        transaction_at TEXT NOT NULL,
        created_by TEXT,
        created_at TEXT
      )
    ''');
    await _addColumnIfMissing(
      table: 'account_transactions',
      column: 'source_event_key',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'account_transactions',
      column: 'reversal_of_transaction_id',
      definition: 'TEXT',
    );

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS mobile_service_providers (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS mobile_service_charge_rules (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        provider_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS mobile_service_transactions (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        provider_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        status TEXT NOT NULL,
        transaction_at TEXT NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');
    // ════════════════════════════════════════
    // EXPENSE MANAGEMENT
    // ════════════════════════════════════════

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS expense_categories (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT,
        name TEXT NOT NULL,
        description TEXT,
        is_system INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_by TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS expenses (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        category_id TEXT,
        category_name TEXT,
        title TEXT NOT NULL,
        expense_date TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        payment_mode TEXT NOT NULL DEFAULT 'cash',
        account_id TEXT,
        ledger_transaction_id TEXT,
        reversal_ledger_transaction_id TEXT,
        payee TEXT,
        notes TEXT,
        receipt_photo_path TEXT,
        local_receipt_path TEXT,
        status TEXT NOT NULL DEFAULT 'confirmed',
        source TEXT NOT NULL DEFAULT 'manual',
        recurring_rule_id TEXT,
        recurring_due_date TEXT,
        created_by TEXT,
        confirmed_by TEXT,
        voided_by TEXT,
        confirmed_at TEXT,
        voided_at TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await _addColumnIfMissing(
      table: 'expenses',
      column: 'account_id',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'expenses',
      column: 'ledger_transaction_id',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      table: 'expenses',
      column: 'reversal_ledger_transaction_id',
      definition: 'TEXT',
    );

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS recurring_expense_rules (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        category_id TEXT,
        category_name TEXT NOT NULL,
        title TEXT NOT NULL,
        estimated_amount REAL NOT NULL DEFAULT 0,
        payment_mode TEXT NOT NULL DEFAULT 'cash',
        account_id TEXT,
        payee TEXT,
        note TEXT,
        frequency TEXT NOT NULL DEFAULT 'monthly',
        interval_count INTEGER NOT NULL DEFAULT 1,
        start_date TEXT NOT NULL,
        end_date TEXT,
        next_due_date TEXT NOT NULL,
        reminder_days_before INTEGER NOT NULL DEFAULT 3,
        status TEXT NOT NULL DEFAULT 'active',
        created_by TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await _addColumnIfMissing(
      table: 'recurring_expense_rules',
      column: 'account_id',
      definition: 'TEXT',
    );
    // ════════════════════════════════════════
    // REPORTING & ANALYTICS
    // ════════════════════════════════════════

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS sales_report_schedules (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT,
        name TEXT NOT NULL,
        cadence TEXT NOT NULL DEFAULT 'daily',
        report_scope TEXT NOT NULL DEFAULT 'branch',
        export_format TEXT NOT NULL DEFAULT 'csv',
        send_to_email TEXT NOT NULL,
        include_product_breakdown INTEGER NOT NULL DEFAULT 1,
        include_customer_breakdown INTEGER NOT NULL DEFAULT 1,
        include_branch_breakdown INTEGER NOT NULL DEFAULT 1,
        include_category_breakdown INTEGER NOT NULL DEFAULT 1,
        next_run_at TEXT NOT NULL,
        last_run_at TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_by TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS sales_report_delivery_jobs (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        schedule_id TEXT,
        branch_id TEXT,
        date_from TEXT NOT NULL,
        date_to TEXT NOT NULL,
        export_format TEXT NOT NULL,
        send_to_email TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT,
        created_at TEXT,
        processed_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS sales_report_cache (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT,
        date_from TEXT NOT NULL,
        date_to TEXT NOT NULL,
        report_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS business_report_schedules (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT,
        name TEXT NOT NULL,
        report_type TEXT NOT NULL,
        cadence TEXT NOT NULL DEFAULT 'daily',
        report_scope TEXT NOT NULL DEFAULT 'branch',
        export_format TEXT NOT NULL DEFAULT 'csv',
        send_to_email TEXT NOT NULL,
        next_run_at TEXT NOT NULL,
        last_run_at TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_by TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS business_report_delivery_jobs (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        schedule_id TEXT,
        branch_id TEXT,
        report_type TEXT NOT NULL,
        date_from TEXT NOT NULL,
        date_to TEXT NOT NULL,
        export_format TEXT NOT NULL,
        send_to_email TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT,
        created_at TEXT,
        processed_at TEXT
      )
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS business_report_cache (
        id TEXT PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT,
        report_type TEXT NOT NULL,
        date_from TEXT NOT NULL,
        date_to TEXT NOT NULL,
        report_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_sales_report_schedules_tenant ON sales_report_schedules(tenant_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_sales_report_schedules_branch ON sales_report_schedules(branch_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_sales_report_schedules_status ON sales_report_schedules(status)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_sales_report_schedules_next_run ON sales_report_schedules(next_run_at)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_sales_report_jobs_tenant ON sales_report_delivery_jobs(tenant_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_sales_report_jobs_status ON sales_report_delivery_jobs(status)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_sales_report_cache_lookup ON sales_report_cache(tenant_id, branch_id, date_from, date_to)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_business_report_schedules_tenant ON business_report_schedules(tenant_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_business_report_schedules_branch ON business_report_schedules(branch_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_business_report_schedules_status ON business_report_schedules(status)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_business_report_schedules_next_run ON business_report_schedules(next_run_at)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_business_report_jobs_tenant ON business_report_delivery_jobs(tenant_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_business_report_jobs_status ON business_report_delivery_jobs(status)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_business_report_cache_lookup ON business_report_cache(tenant_id, branch_id, report_type, date_from, date_to)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expense_categories_tenant ON expense_categories(tenant_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expense_categories_branch ON expense_categories(branch_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expenses_tenant ON expenses(tenant_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expenses_branch ON expenses(branch_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expenses_category ON expenses(category_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expenses_date ON expenses(expense_date)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expenses_status ON expenses(status)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expenses_source ON expenses(source)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_expenses_recurring_rule ON expenses(recurring_rule_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_recurring_expense_rules_tenant ON recurring_expense_rules(tenant_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_recurring_expense_rules_branch ON recurring_expense_rules(branch_id)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_recurring_expense_rules_next_due ON recurring_expense_rules(next_due_date)',
    );

    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_recurring_expense_rules_status ON recurring_expense_rules(status)',
    );
    // Indexes searches ko fast karte hain.
    // Example:
    // branch ke tickets load karna
    // status wise filter karna
    // IMEI se ticket find karna
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_inventory_units_branch
      ON inventory_units(branch_id)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_inventory_units_product
      ON inventory_units(product_id)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_inventory_units_imei
      ON inventory_units(imei)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_inventory_units_status
      ON inventory_units(status)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_repair_tickets_branch
      ON repair_tickets(branch_id)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_repair_tickets_status
      ON repair_tickets(status)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_repair_tickets_customer
      ON repair_tickets(customer_id)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_repair_tickets_technician
      ON repair_tickets(technician_id)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_repair_tickets_imei
      ON repair_tickets(imei)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_repair_tickets_created_at
      ON repair_tickets(created_at)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_repair_status_logs_ticket
      ON repair_status_logs(ticket_id, created_at)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_repair_status_logs_branch
      ON repair_status_logs(branch_id)
    ''');

    // Indexes
    await _db.customStatement('''
    CREATE INDEX IF NOT EXISTS idx_sales_branch
    ON sales(branch_id)
  ''');
    await _db.customStatement('''
    CREATE INDEX IF NOT EXISTS idx_sale_items_sale
    ON sale_items(sale_id)
  ''');
    await _db.customStatement('''
    CREATE INDEX IF NOT EXISTS idx_sale_returns_original_sale
    ON sale_returns(original_sale_id)
  ''');
    await _db.customStatement('''
    CREATE INDEX IF NOT EXISTS idx_sale_return_items_sale
    ON sale_return_items(original_sale_id)
  ''');
    await _db.customStatement('''
    CREATE INDEX IF NOT EXISTS idx_customers_branch
    ON customers(branch_id)
  ''');
    await _db.customStatement('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_tenant_phone
    ON customers(tenant_id, phone)
    WHERE phone IS NOT NULL AND phone != ''
  ''');
    await _db.customStatement('''
    CREATE INDEX IF NOT EXISTS idx_customer_settlements_customer
    ON customer_settlements(customer_id)
  ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_products_branch
      ON products(branch_id)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_products_branch_active_name
      ON products(branch_id, is_active, name COLLATE NOCASE)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_products_branch_active_sku
      ON products(branch_id, is_active, sku COLLATE NOCASE)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_products_branch_category_active_name
      ON products(branch_id, category_id, is_active, name COLLATE NOCASE)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_products_branch_updated
      ON products(branch_id, updated_at)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_products_branch_active_sale_price
      ON products(branch_id, is_active, sale_price)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_inventory_branch_quantity
      ON inventory(branch_id, quantity)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_categories_branch
      ON categories(branch_id)
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_branches_tenant
      ON branches(tenant_id)
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_stock_adjustments_product
      ON stock_adjustments(product_id);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_stock_adjustments_branch
      ON stock_adjustments(branch_id);

    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_stock_adjustments_created
      ON stock_adjustments(created_at);

    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_tenant_settings_tenant
      ON tenant_settings(tenant_id);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_accounts_branch
      ON accounts(branch_id);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_account_transactions_branch
      ON account_transactions(branch_id, transaction_at);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_account_transactions_account
      ON account_transactions(account_id, transaction_at);
    ''');
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_account_transactions_source_event
      ON account_transactions(tenant_id, branch_id, source_event_key)
      WHERE source_event_key IS NOT NULL;
    ''');
    await _db.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS uq_account_transactions_reversal
      ON account_transactions(reversal_of_transaction_id)
      WHERE reversal_of_transaction_id IS NOT NULL;
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_mobile_service_providers_branch
      ON mobile_service_providers(branch_id, is_active, name);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_mobile_service_rules_branch
      ON mobile_service_charge_rules(
        branch_id, provider_id, operation, is_active
      );
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_mobile_service_transactions_branch
      ON mobile_service_transactions(branch_id, transaction_at DESC);
    ''');
  }

  static Future<void> _makeProcurementProductLinksNullable() async {
    final poInfo =
        await _db.customSelect('PRAGMA table_info(purchase_order_items)').get();
    final receiptInfo =
        await _db.customSelect('PRAGMA table_info(goods_receipt_items)').get();
    final poProduct = poInfo.where((row) => row.data['name'] == 'product_id');
    final receiptProduct = receiptInfo.where(
      (row) => row.data['name'] == 'product_id',
    );
    if (poProduct.isNotEmpty && poProduct.single.data['notnull'] == 1) {
      await _db.transaction(() async {
        await _db.customStatement(
          'ALTER TABLE purchase_order_items RENAME TO purchase_order_items_old',
        );
        await _db.customStatement('''
          CREATE TABLE purchase_order_items (
            id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL,
            purchase_order_id TEXT NOT NULL, product_id TEXT,
            product_resolution TEXT NOT NULL DEFAULT 'existing_product',
            product_draft_json TEXT, resolved_product_id TEXT,
            product_name TEXT NOT NULL, product_sku TEXT,
            ordered_quantity INTEGER NOT NULL,
            received_quantity INTEGER NOT NULL DEFAULT 0,
            negotiated_unit_cost REAL NOT NULL DEFAULT 0,
            actual_unit_cost REAL, line_total REAL NOT NULL DEFAULT 0,
            created_at TEXT
          )
        ''');
        await _db.customStatement('''
          INSERT INTO purchase_order_items
          SELECT id, tenant_id, purchase_order_id, product_id,
            product_resolution, product_draft_json, resolved_product_id,
            product_name, product_sku, ordered_quantity, received_quantity,
            negotiated_unit_cost, actual_unit_cost, line_total, created_at
          FROM purchase_order_items_old
        ''');
        await _db.customStatement('DROP TABLE purchase_order_items_old');
      });
    }
    if (receiptProduct.isNotEmpty &&
        receiptProduct.single.data['notnull'] == 1) {
      await _db.transaction(() async {
        await _db.customStatement(
          'ALTER TABLE goods_receipt_items RENAME TO goods_receipt_items_old',
        );
        await _db.customStatement('''
          CREATE TABLE goods_receipt_items (
            id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL,
            goods_receipt_id TEXT NOT NULL, purchase_order_id TEXT NOT NULL,
            purchase_order_item_id TEXT NOT NULL, product_id TEXT,
            item_resolution TEXT NOT NULL DEFAULT 'existing_product',
            item_name TEXT, received_quantity INTEGER NOT NULL,
            actual_unit_cost REAL NOT NULL DEFAULT 0,
            update_product_cost INTEGER NOT NULL DEFAULT 0,
            line_total REAL NOT NULL DEFAULT 0, created_at TEXT
          )
        ''');
        await _db.customStatement('''
          INSERT INTO goods_receipt_items(
            id, tenant_id, goods_receipt_id, purchase_order_id,
            purchase_order_item_id, product_id, received_quantity,
            actual_unit_cost, update_product_cost, line_total, created_at
          )
          SELECT id, tenant_id, goods_receipt_id, purchase_order_id,
            purchase_order_item_id, product_id, received_quantity,
            actual_unit_cost, update_product_cost, line_total, created_at
          FROM goods_receipt_items_old
        ''');
        await _db.customStatement('DROP TABLE goods_receipt_items_old');
      });
    }
  }

  static Future<void> _addColumnIfMissing({
    required String table,
    required String column,
    required String definition,
  }) async {
    final rows = await _db.customSelect('PRAGMA table_info($table)').get();
    final exists = rows.any((row) => row.data['name'] == column);
    if (!exists) {
      await _db.customStatement(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }
  }
}

class _RawLocalDatabase extends GeneratedDatabase {
  _RawLocalDatabase(super.executor);

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  int get schemaVersion => 1;
}
