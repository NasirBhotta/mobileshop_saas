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
        COALESCE(i.quantity, 0) AS stock
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
        sale_price, cost_price, imei_tracked, is_active, created_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        5,
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
        id, tenant_id, branch_id, name, created_at
      ) VALUES(?, ?, ?, ?, ?)
      ''',
      [
        category.id,
        category.tenantId,
        category.branchId,
        category.name,
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
      updated_at
    )
    VALUES (?, ?, ?, ?)
    ''',
      [
        settings['tenant_id'],
        settings['adjustment_qty_threshold'],
        settings['adjustment_value_threshold'],
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
}
