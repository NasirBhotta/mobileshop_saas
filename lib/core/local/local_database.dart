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
          updated_at TEXT
        )
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
