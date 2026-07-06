import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LocalDatabase {
  LocalDatabase._();

  static final QueryExecutor _executor = LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(path.join(directory.path, 'mobileshop_saas.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
  static final GeneratedDatabase _db = _RawLocalDatabase(_executor);
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await _db.customStatement('PRAGMA foreign_keys = ON');
    await _createTables();
    _initialized = true;
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
        description TEXT,
        sale_price REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        reorder_threshold INTEGER NOT NULL DEFAULT 0,
        imei_tracked INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT
      )
    ''');

    await _addColumnIfMissing(
      table: 'categories',
      column: 'default_reorder_threshold',
      definition: 'INTEGER NOT NULL DEFAULT 5',
    );
    await _addColumnIfMissing(
      table: 'products',
      column: 'reorder_threshold',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS inventory (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
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
      product_id TEXT NOT NULL,
      product_name TEXT NOT NULL,
      product_sku TEXT,
      quantity INTEGER NOT NULL,
      unit_price REAL NOT NULL,
      discount_amount REAL NOT NULL DEFAULT 0,
      tax_rate REAL NOT NULL DEFAULT 0,
      line_total REAL NOT NULL
    )
  ''');

    await _db.customStatement('''
    CREATE TABLE IF NOT EXISTS sale_payments (
      id TEXT PRIMARY KEY,
      sale_id TEXT NOT NULL,
      method TEXT NOT NULL,
      amount REAL NOT NULL
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
      notes TEXT,
      synced INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
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
      refund_amount REAL NOT NULL DEFAULT 0
    )
  ''');

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
