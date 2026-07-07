import 'dart:convert';

import 'package:mobileshop_saas/features/pos/data/models/cart_item_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_dashboard_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/held_cart_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/inventory/data/models/category_model.dart';
import '../../features/inventory/data/models/product_model.dart';
import '../../features/onboarding/data/models/shop_setup_model.dart';
import '../local/local_store.dart';

class OfflineMutation {
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const OfflineMutation({
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  factory OfflineMutation.fromMap(Map<String, dynamic> map) {
    return OfflineMutation(
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
  };
}

class OfflineStore {
  const OfflineStore._();

  static String _profileKey(String userId) => 'offline.profile.$userId';
  static String _tenantKey(String tenantId) => 'offline.tenant.$tenantId';
  static String _branchesKey(String tenantId) => 'offline.branches.$tenantId';
  static String _selectedBranchKey(String userId) =>
      'offline.selected_branch.$userId';
  static String _productsKey(String branchId) => 'offline.products.$branchId';
  static String _categoriesKey(String branchId) =>
      'offline.categories.$branchId';
  static String _mutationsKey(String userId) => 'offline.mutations.$userId';
  static String _tenantSettingsKey(String tenantId) =>
      'offline.tenant_settings.$tenantId';

  static String _stockAdjustmentsKey(String branchId) =>
      'offline.stock_adjustments.$branchId';

  static String _salesKey(String branchId) => 'offline.sales.$branchId';
  static String _heldCartsKey(String branchId) =>
      'offline.held_carts.$branchId';

  static Future<void> saveProfile(
    String userId,
    Map<String, dynamic> profile,
  ) async {
    try {
      await LocalStore.saveProfile(userId, profile);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey(userId), jsonEncode(profile));
    final branchId = profile['branch_id'] as String?;
    if (branchId != null) {
      await prefs.setString(_selectedBranchKey(userId), branchId);
    }
  }

  static Future<Map<String, dynamic>?> loadProfile(String userId) async {
    try {
      final profile = await LocalStore.loadProfile(userId);
      if (profile != null) return profile;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey(userId));
    if (raw == null) return null;

    final profile = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final selectedBranchId = prefs.getString(_selectedBranchKey(userId));
    if (selectedBranchId != null) {
      profile['branch_id'] = selectedBranchId;
    }
    return profile;
  }

  static Future<void> saveTenant(
    String tenantId,
    Map<String, dynamic> tenant,
  ) async {
    try {
      await LocalStore.saveTenant(tenantId, tenant);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tenantKey(tenantId), jsonEncode(tenant));
  }

  static Future<Map<String, dynamic>?> loadTenant(String tenantId) async {
    try {
      final tenant = await LocalStore.loadTenant(tenantId);
      if (tenant != null) return tenant;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tenantKey(tenantId));
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> saveBranches(
    String tenantId,
    List<BranchInputModel> branches,
  ) async {
    try {
      await LocalStore.saveBranches(tenantId, branches);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _branchesKey(tenantId),
      jsonEncode(branches.map((branch) => branch.toCacheMap()).toList()),
    );
  }

  static Future<List<BranchInputModel>> loadBranches(String tenantId) async {
    try {
      final branches = await LocalStore.loadBranches(tenantId);
      if (branches.isNotEmpty) return branches;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_branchesKey(tenantId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((row) => BranchInputModel.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<void> selectBranch({
    required String userId,
    required String branchId,
  }) async {
    try {
      await LocalStore.selectBranch(userId: userId, branchId: branchId);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedBranchKey(userId), branchId);
    final profile = await loadProfile(userId);
    if (profile != null) {
      profile['branch_id'] = branchId;
      await saveProfile(userId, profile);
    }
  }

  static Future<String?> loadSelectedBranchId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedBranchKey(userId));
  }

  static Future<void> saveProducts(
    String branchId,
    List<ProductModel> products,
  ) async {
    try {
      await LocalStore.saveProducts(branchId, products);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _productsKey(branchId),
      jsonEncode(products.map((product) => product.toCacheMap()).toList()),
    );
  }

  static Future<List<ProductModel>> loadProducts(String branchId) async {
    try {
      final products = await LocalStore.loadProducts(branchId);
      if (products.isNotEmpty) return products;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_productsKey(branchId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((row) => ProductModel.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<void> upsertCachedProduct(ProductModel product) async {
    try {
      await LocalStore.upsertProduct(product);
    } catch (_) {}

    final products = await loadProducts(product.branchId);
    final nextProducts = [
      for (final item in products)
        if (item.id != product.id) item,
      product,
    ]..sort((a, b) => a.name.compareTo(b.name));
    await saveProducts(product.branchId, nextProducts);
  }

  static Future<void> deactivateCachedProduct({
    required String branchId,
    required String productId,
  }) async {
    try {
      await LocalStore.deactivateProduct(
        branchId: branchId,
        productId: productId,
      );
    } catch (_) {}

    final products = await loadProducts(branchId);
    await saveProducts(
      branchId,
      products.where((product) => product.id != productId).toList(),
    );
  }

  static Future<void> saveCategories(
    String branchId,
    List<CategoryModel> categories,
  ) async {
    try {
      await LocalStore.saveCategories(branchId, categories);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _categoriesKey(branchId),
      jsonEncode(categories.map((category) => category.toCacheMap()).toList()),
    );
  }

  static Future<List<CategoryModel>> loadCategories(String branchId) async {
    try {
      final categories = await LocalStore.loadCategories(branchId);
      if (categories.isNotEmpty) return categories;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_categoriesKey(branchId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((row) => CategoryModel.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<void> saveTenantSettings(
    String tenantId,
    Map<String, dynamic> settings,
  ) async {
    try {
      await LocalStore.saveTenantSettings(settings);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_tenantSettingsKey(tenantId), jsonEncode(settings));
  }

  static Future<Map<String, dynamic>?> loadTenantSettings(
    String tenantId,
  ) async {
    try {
      final settings = await LocalStore.loadTenantSettings(tenantId);
      if (settings != null) return settings;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_tenantSettingsKey(tenantId));

    if (raw == null) return null;

    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> saveStockAdjustments(
    String branchId,
    List<Map<String, dynamic>> adjustments,
  ) async {
    try {
      await LocalStore.saveStockAdjustments(adjustments);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _stockAdjustmentsKey(branchId),
      jsonEncode(adjustments),
    );
  }

  static Future<List<Map<String, dynamic>>> loadStockAdjustments(
    String branchId, {
    String? productId,
  }) async {
    try {
      final adjustments = await LocalStore.loadStockAdjustments(
        branchId,
        productId: productId,
      );

      if (adjustments.isNotEmpty) {
        return adjustments;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_stockAdjustmentsKey(branchId));

    if (raw == null) return [];

    final adjustments =
        (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    if (productId == null) return adjustments;
    return adjustments.where((e) => e['product_id'] == productId).toList();
  }

  static Future<void> upsertStockAdjustment(
    String branchId,
    Map<String, dynamic> adjustment,
  ) async {
    try {
      await LocalStore.saveStockAdjustment(adjustment);
    } catch (_) {}

    final adjustments = await loadStockAdjustments(branchId);

    adjustments.removeWhere((e) => e['id'] == adjustment['id']);

    adjustments.insert(0, adjustment);

    await saveStockAdjustments(branchId, adjustments);
  }

  static Future<void> enqueueMutation({
    required String userId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final mutations = await loadMutations(userId);
    mutations.add(
      OfflineMutation(type: type, payload: payload, createdAt: DateTime.now()),
    );
    await saveMutations(userId, mutations);
  }

  static Future<List<OfflineMutation>> loadMutations(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mutationsKey(userId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((row) => OfflineMutation.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<void> saveMutations(
    String userId,
    List<OfflineMutation> mutations,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _mutationsKey(userId),
      jsonEncode(mutations.map((mutation) => mutation.toMap()).toList()),
    );
  }

  // ════════════════════════════════════════
  // SALES
  // ════════════════════════════════════════

  static Future<void> saveSale(SaleModel sale) async {
    // SQLite mein save karo
    try {
      await LocalStore.saveSale(sale);
    } catch (_) {}

    // SharedPrefs fallback
    final prefs = await SharedPreferences.getInstance();
    final sales = await loadSales(sale.branchId);

    // Naya sale add karo (duplicate check)
    final updated = [
      for (final s in sales)
        if (s.id != sale.id) s,
      sale,
    ];

    await prefs.setString(
      _salesKey(sale.branchId),
      jsonEncode(updated.map((s) => _saleToMap(s)).toList()),
    );
  }

  static Future<List<SaleModel>> loadSales(String branchId) async {
    // SQLite se try karo
    try {
      final sales = await LocalStore.loadSales(branchId);
      if (sales.isNotEmpty) return sales;
    } catch (_) {}

    // SharedPrefs fallback
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_salesKey(branchId));
    if (raw == null) return [];

    return (jsonDecode(raw) as List)
        .map((e) => SaleModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // Stock decrement (offline sale ke baad)
  static Future<void> decrementStock({
    required String branchId,
    required String productId,
    required int quantity,
  }) async {
    final products = await loadProducts(branchId);
    var productFound = false;
    final updated =
        products.map((p) {
          if (p.id != productId) return p;
          productFound = true;
          final newStock = ((p.stock - quantity).clamp(0, 999999)).toInt();
          return ProductModel(
            id: p.id,
            tenantId: p.tenantId,
            branchId: p.branchId,
            categoryId: p.categoryId,
            categoryName: p.categoryName,
            name: p.name,
            sku: p.sku,
            description: p.description,
            salePrice: p.salePrice,
            costPrice: p.costPrice,
            imeiTracked: p.imeiTracked,
            isActive: p.isActive,
            stock: newStock,
            reorderThreshold: p.reorderThreshold,
            branchThreshold: p.branchThreshold,
            categoryThreshold: p.categoryThreshold,
          );
        }).toList();

    if (productFound) {
      await saveProducts(branchId, updated);
      return;
    }

    try {
      await LocalStore.decrementStock(
        branchId: branchId,
        productId: productId,
        quantity: quantity,
      );
    } catch (_) {}
  }

  // ════════════════════════════════════════
  // HELD CARTS
  // ════════════════════════════════════════

  static Future<void> incrementStock({
    required String branchId,
    required String productId,
    required int quantity,
  }) async {
    final products = await loadProducts(branchId);
    var productFound = false;
    final updated =
        products.map((p) {
          if (p.id != productId) return p;
          productFound = true;
          final newStock = ((p.stock + quantity).clamp(0, 999999)).toInt();
          return ProductModel(
            id: p.id,
            tenantId: p.tenantId,
            branchId: p.branchId,
            categoryId: p.categoryId,
            categoryName: p.categoryName,
            name: p.name,
            sku: p.sku,
            description: p.description,
            salePrice: p.salePrice,
            costPrice: p.costPrice,
            imeiTracked: p.imeiTracked,
            isActive: p.isActive,
            stock: newStock,
            reorderThreshold: p.reorderThreshold,
            branchThreshold: p.branchThreshold,
            categoryThreshold: p.categoryThreshold,
          );
        }).toList();

    if (productFound) {
      await saveProducts(branchId, updated);
      return;
    }

    try {
      await LocalStore.incrementStock(
        branchId: branchId,
        productId: productId,
        quantity: quantity,
      );
    } catch (_) {}
  }

  static Future<void> saveHeldCart(HeldCartModel cart) async {
    try {
      await LocalStore.saveHeldCart(cart);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final carts = await loadHeldCarts(cart.branchId);

    final updated = [
      for (final c in carts)
        if (c.id != cart.id) c,
      cart,
    ];

    await prefs.setString(
      _heldCartsKey(cart.branchId),
      jsonEncode(
        updated
            .map(
              (c) => {
                'id': c.id,
                'branch_id': c.branchId,
                'user_id': c.userId,
                'label': c.label,
                'cart_data': c.toCartData(),
                'created_at': c.createdAt.toIso8601String(),
                'expires_at': c.expiresAt?.toIso8601String(),
              },
            )
            .toList(),
      ),
    );
  }

  static Future<List<HeldCartModel>> loadHeldCarts(String branchId) async {
    try {
      final carts = await LocalStore.loadHeldCarts(branchId);
      if (carts.isNotEmpty) return carts;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_heldCartsKey(branchId));
    if (raw == null) return [];

    return (jsonDecode(raw) as List).map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      final cartData = map['cart_data'] as Map<String, dynamic>;
      final itemsList = cartData['items'] as List<dynamic>? ?? [];

      return HeldCartModel(
        id: map['id'] as String?,
        branchId: map['branch_id'] as String,
        userId: map['user_id'] as String,
        label: map['label'] as String?,
        customerId: cartData['customer_id'] as String?,
        customerName: cartData['customer_name'] as String?,
        items:
            itemsList
                .map(
                  (i) => CartItemModel.fromMap(
                    Map<String, dynamic>.from(i as Map),
                  ),
                )
                .toList(),
        createdAt: DateTime.parse(map['created_at'] as String),
        expiresAt:
            map['expires_at'] != null
                ? DateTime.parse(map['expires_at'] as String)
                : null,
      );
    }).toList();
  }

  static Future<void> deleteHeldCart({
    required String branchId,
    required String cartId,
  }) async {
    try {
      await LocalStore.deleteHeldCart(cartId);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final carts = await loadHeldCarts(branchId);
    await prefs.setString(
      _heldCartsKey(branchId),
      jsonEncode(
        carts.where((c) => c.id != cartId).map((c) => c.toCartData()).toList(),
      ),
    );
  }

  // ════════════════════════════════════════
  // CUSTOMERS
  // ════════════════════════════════════════

  static Future<void> saveCustomer(CustomerModel customer) async {
    try {
      await LocalStore.saveCustomer(customer);
    } catch (_) {}
  }

  static Future<List<CustomerModel>> searchCustomers({
    required String branchId,
    required String query,
  }) async {
    try {
      return await LocalStore.searchCustomers(branchId: branchId, query: query);
    } catch (_) {}
    return [];
  }

  static Future<List<CustomerModel>> loadCustomers({
    required String branchId,
    String query = '',
    int limit = 100,
  }) async {
    try {
      return await LocalStore.loadCustomers(
        branchId: branchId,
        query: query,
        limit: limit,
      );
    } catch (_) {}
    return [];
  }

  static Future<CustomerModel?> loadCustomerById(String customerId) async {
    try {
      return await LocalStore.loadCustomerById(customerId);
    } catch (_) {}
    return null;
  }

  static Future<CustomerModel?> loadCustomerByPhone({
    required String tenantId,
    required String phone,
  }) async {
    try {
      return await LocalStore.loadCustomerByPhone(
        tenantId: tenantId,
        phone: phone,
      );
    } catch (_) {}
    return null;
  }

  static Future<void> updateCustomerCredit({
    required String customerId,
    double? creditLimit,
    bool clearCreditLimit = false,
    double? outstandingBalance,
  }) async {
    try {
      await LocalStore.updateCustomerCredit(
        customerId: customerId,
        creditLimit: creditLimit,
        clearCreditLimit: clearCreditLimit,
        outstandingBalance: outstandingBalance,
      );
    } catch (_) {}
  }

  static Future<void> adjustCustomerOutstanding({
    required String customerId,
    required double delta,
  }) async {
    try {
      await LocalStore.adjustCustomerOutstanding(
        customerId: customerId,
        delta: delta,
      );
    } catch (_) {}
  }

  static Future<void> saveCustomerSettlement(
    CustomerSettlementModel settlement, {
    bool synced = false,
  }) async {
    try {
      await LocalStore.saveCustomerSettlement(settlement, synced: synced);
    } catch (_) {}
  }

  static Future<List<CustomerSettlementModel>> loadCustomerSettlements(
    String customerId,
  ) async {
    try {
      return await LocalStore.loadCustomerSettlements(customerId);
    } catch (_) {}
    return [];
  }

  // ── Helper ──
  static Map<String, dynamic> _saleToMap(SaleModel sale) => {
    'id': sale.id,
    'branch_id': sale.branchId,
    'customer_id': sale.customerId,
    'customer_name': sale.customerName,
    'user_id': sale.userId,
    'status': sale.status.code,
    'subtotal': sale.subtotal,
    'discount_amount': sale.discountAmount,
    'tax_amount': sale.taxAmount,
    'total': sale.total,
    'notes': sale.notes,
    'void_reason': sale.voidReason,
    'created_at': sale.createdAt?.toIso8601String(),
    'sale_items': sale.items.map((i) => i.toMap()).toList(),
    'sale_payments': sale.payments.map((p) => p.toMap()).toList(),
  };
}
