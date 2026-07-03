import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/inventory/data/models/category_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/price_history_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class InventoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  Future<Map<String, dynamic>> _currentProfile() async {
    Map<String, dynamic>? profile;
    try {
      profile =
          await _client
              .from('users')
              .select('id, tenant_id, branch_id, full_name, email, phone, role')
              .eq('id', _currentUser.id)
              .maybeSingle();
      if (profile != null) {
        final selectedBranchId = await OfflineStore.loadSelectedBranchId(
          _currentUser.id,
        );
        if (selectedBranchId != null) {
          profile['branch_id'] = selectedBranchId;
        }
        await OfflineStore.saveProfile(_currentUser.id, profile);
      }
    } catch (_) {
      profile = await OfflineStore.loadProfile(_currentUser.id);
    }

    if (profile == null) throw Exception('User profile not found');
    return profile;
  }

  Future<String> _currentTenantId() async {
    final profile = await _currentProfile();
    final tenantId = profile['tenant_id'] as String?;
    if (tenantId == null) throw Exception('User tenant not found');
    return tenantId;
  }

  Future<String> _currentBranchId(String tenantId) async {
    final profile = await _currentProfile();
    final selectedBranchId = profile['branch_id'] as String?;
    if (selectedBranchId != null) return selectedBranchId;

    final branch =
        await _client
            .from('branches')
            .select('id')
            .eq('tenant_id', tenantId)
            .order('id')
            .limit(1)
            .maybeSingle();

    final branchId = branch?['id'] as String?;
    if (branchId == null) throw Exception('Branch not found');
    return branchId;
  }

  // ── Products ──
  Future<List<ProductModel>> fetchProducts({String? categoryId}) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    await syncOfflineMutations();

    try {
      var query = _client
          .from('products')
          .select('*, categories(name), inventory!inner(quantity, branch_id)')
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .eq('inventory.branch_id', branchId)
          .eq('is_active', true);

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      final data = await query.order('name');
      final products =
          (data as List).map((e) => ProductModel.fromMap(e)).toList();
      await OfflineStore.saveProducts(branchId, products);
      return products;
    } catch (_) {
      final products = await OfflineStore.loadProducts(branchId);
      if (categoryId == null) return products;
      return products
          .where((product) => product.categoryId == categoryId)
          .toList();
    }
  }

  Future<ProductModel> addProduct(ProductModel product) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data =
          await _client
              .from('products')
              .insert(
                product.toInsertMap(tenantId: tenantId, branchId: branchId),
              )
              .select('id')
              .single();

      final productId = data['id'] as String;
      await setStock(
        productId: productId,
        branchId: branchId,
        quantity: product.stock,
      );

      final savedProduct = await fetchProduct(productId);
      await OfflineStore.upsertCachedProduct(savedProduct);
      return savedProduct;
    } catch (_) {
      final offlineProduct = await _offlineProduct(
        product: product,
        tenantId: tenantId,
        branchId: branchId,
        id: product.id.isEmpty ? const Uuid().v4() : product.id,
      );
      await OfflineStore.upsertCachedProduct(offlineProduct);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_product',
        payload: {'product': offlineProduct.toCacheMap()},
      );
      return offlineProduct;
    }
  }

  Future<ProductModel> updateProduct(ProductModel product) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      await _client
          .from('products')
          .update(product.toInsertMap(tenantId: tenantId, branchId: branchId))
          .eq('id', product.id)
          .eq('branch_id', branchId)
          .eq('tenant_id', tenantId);

      await setStock(
        productId: product.id,
        branchId: branchId,
        quantity: product.stock,
      );

      final savedProduct = await fetchProduct(product.id);
      await OfflineStore.upsertCachedProduct(savedProduct);
      return savedProduct;
    } catch (_) {
      final offlineProduct = await _offlineProduct(
        product: product,
        tenantId: tenantId,
        branchId: branchId,
      );
      await OfflineStore.upsertCachedProduct(offlineProduct);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_product',
        payload: {'product': offlineProduct.toCacheMap()},
      );
      return offlineProduct;
    }
  }

  Future<ProductModel> fetchProduct(String productId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data =
          await _client
              .from('products')
              .select(
                '*, categories(name), inventory!inner(quantity, branch_id)',
              )
              .eq('tenant_id', tenantId)
              .eq('branch_id', branchId)
              .eq('inventory.branch_id', branchId)
              .eq('id', productId)
              .single();

      final product = ProductModel.fromMap(data);
      await OfflineStore.upsertCachedProduct(product);
      return product;
    } catch (_) {
      final products = await OfflineStore.loadProducts(branchId);
      return products.firstWhere((product) => product.id == productId);
    }
  }

  Future<void> deleteProduct(String productId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      await _client
          .from('products')
          .update({'is_active': false})
          .eq('id', productId)
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId);
    } catch (_) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'delete_product',
        payload: {
          'product_id': productId,
          'tenant_id': tenantId,
          'branch_id': branchId,
        },
      );
    }
    await OfflineStore.deactivateCachedProduct(
      branchId: branchId,
      productId: productId,
    );
  }

  // ── Bulk Pricing / Price History / IMEI Guards ──
  Future<int> bulkUpdateProductPrices({
    required List<ProductModel> products,
    required double percentage,
    required String direction,
  }) async {
    final productIds = products.map((product) => product.id).toList();

    try {
      final updatedCount = await _client.rpc(
        'bulk_update_product_prices',
        params: {
          'p_product_ids': productIds,
          'p_percentage': percentage,
          'p_direction': direction,
        },
      );

      return (updatedCount as num).toInt();
    } catch (_) {
      return _bulkUpdateProductPricesDirectly(
        products: products,
        percentage: percentage,
        direction: direction,
      );
    }
  }

  Future<int> _bulkUpdateProductPricesDirectly({
    required List<ProductModel> products,
    required double percentage,
    required String direction,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final multiplier =
        direction == 'markup' ? 1 + (percentage / 100) : 1 - (percentage / 100);
    var updatedCount = 0;

    for (final product in products) {
      final newPrice = ((product.salePrice * multiplier) * 100).round() / 100;
      final updatedProduct = ProductModel(
        id: product.id,
        tenantId: product.tenantId,
        branchId: product.branchId,
        categoryId: product.categoryId,
        categoryName: product.categoryName,
        name: product.name,
        sku: product.sku,
        description: product.description,
        salePrice: newPrice,
        costPrice: product.costPrice,
        imeiTracked: product.imeiTracked,
        isActive: product.isActive,
        stock: product.stock,
      );

      try {
        final updatedRows = await _client
            .from('products')
            .update({'sale_price': newPrice})
            .eq('id', product.id)
            .eq('branch_id', branchId)
            .eq('tenant_id', tenantId)
            .eq('is_active', true)
            .select('id');

        if ((updatedRows as List).isEmpty) continue;
      } catch (_) {
        await OfflineStore.enqueueMutation(
          userId: _currentUser.id,
          type: 'upsert_product',
          payload: {'product': updatedProduct.toCacheMap()},
        );
      }

      await OfflineStore.upsertCachedProduct(updatedProduct);
      updatedCount++;
    }

    return updatedCount;
  }

  Future<List<PriceHistoryModel>> fetchPriceHistory(String productId) async {
    final tenantId = await _currentTenantId();
    final data = await _client
        .from('product_price_history')
        .select()
        .eq('tenant_id', tenantId)
        .eq('product_id', productId)
        .order('changed_at', ascending: false)
        .limit(50);

    return (data as List).map((e) => PriceHistoryModel.fromMap(e)).toList();
  }

  Future<bool> productHasActiveImeiUnits(String productId) async {
    final hasUnits = await _client.rpc(
      'product_has_active_imei_units',
      params: {'p_product_id': productId},
    );

    return hasUnits == true;
  }

  // ── Categories ──
  Future<List<CategoryModel>> fetchCategories() async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data = await _client
          .from('categories')
          .select()
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .order('name');

      final categories =
          (data as List).map((e) => CategoryModel.fromMap(e)).toList();
      await OfflineStore.saveCategories(branchId, categories);
      return categories;
    } catch (_) {
      return OfflineStore.loadCategories(branchId);
    }
  }

  Future<CategoryModel> addCategory(String name) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data =
          await _client
              .from('categories')
              .insert({
                'tenant_id': tenantId,
                'branch_id': branchId,
                'name': name,
              })
              .select()
              .single();

      final category = CategoryModel.fromMap(data);
      final categories = await OfflineStore.loadCategories(branchId);
      await OfflineStore.saveCategories(
        branchId,
        [...categories.where((item) => item.id != category.id), category]
          ..sort((a, b) => a.name.compareTo(b.name)),
      );
      return category;
    } catch (_) {
      final category = CategoryModel(
        id: const Uuid().v4(),
        tenantId: tenantId,
        branchId: branchId,
        name: name,
      );
      final categories = await OfflineStore.loadCategories(branchId);
      await OfflineStore.saveCategories(
        branchId,
        [...categories.where((item) => item.id != category.id), category]
          ..sort((a, b) => a.name.compareTo(b.name)),
      );
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'upsert_category',
        payload: {'category': category.toCacheMap()},
      );
      return category;
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      await _client
          .from('categories')
          .delete()
          .eq('id', categoryId)
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId);
    } catch (_) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'delete_category',
        payload: {
          'category_id': categoryId,
          'tenant_id': tenantId,
          'branch_id': branchId,
        },
      );
    }

    final categories = await OfflineStore.loadCategories(branchId);
    await OfflineStore.saveCategories(
      branchId,
      categories.where((category) => category.id != categoryId).toList(),
    );
  }

  // ── Stock Adjustment ──
  Future<void> adjustStock({
    required String productId,
    required String branchId,
    required int quantity, // positive = in, negative = out
  }) async {
    // Upsert inventory row
    await _client.from('inventory').upsert({
      'branch_id': branchId,
      'product_id': productId,
      'quantity': quantity,
    }, onConflict: 'branch_id,product_id');
  }

  Future<void> setStock({
    required String productId,
    required String branchId,
    required int quantity,
  }) async {
    await _client.from('inventory').upsert({
      'branch_id': branchId,
      'product_id': productId,
      'quantity': quantity < 0 ? 0 : quantity,
    }, onConflict: 'branch_id,product_id');
  }

  Future<int> getStock({
    required String productId,
    required String branchId,
  }) async {
    final data =
        await _client
            .from('inventory')
            .select('quantity')
            .eq('product_id', productId)
            .eq('branch_id', branchId)
            .maybeSingle();

    return (data?['quantity'] as num?)?.toInt() ?? 0;
  }

  Future<ProductModel> _offlineProduct({
    required ProductModel product,
    required String tenantId,
    required String branchId,
    String? id,
  }) async {
    final categories = await OfflineStore.loadCategories(branchId);
    String? categoryName;
    for (final category in categories) {
      if (category.id == product.categoryId) {
        categoryName = category.name;
        break;
      }
    }

    return ProductModel(
      id: id ?? product.id,
      tenantId: tenantId,
      branchId: branchId,
      categoryId: product.categoryId,
      categoryName: categoryName ?? product.categoryName,
      name: product.name,
      sku: product.sku,
      description: product.description,
      salePrice: product.salePrice,
      costPrice: product.costPrice,
      imeiTracked: product.imeiTracked,
      isActive: product.isActive,
      stock: product.stock,
    );
  }

  Future<void> syncOfflineMutations() async {
    final userId = _currentUser.id;
    final mutations = await OfflineStore.loadMutations(userId);
    if (mutations.isEmpty) return;

    final remaining = <OfflineMutation>[];
    for (final mutation in mutations) {
      try {
        switch (mutation.type) {
          case 'upsert_product':
            await _syncUpsertProduct(mutation.payload);
            break;
          case 'delete_product':
            await _client
                .from('products')
                .update({'is_active': false})
                .eq('id', mutation.payload['product_id'])
                .eq('tenant_id', mutation.payload['tenant_id'])
                .eq('branch_id', mutation.payload['branch_id']);
            break;
          case 'upsert_category':
            await _client
                .from('categories')
                .upsert(
                  mutation.payload['category'] as Map<String, dynamic>,
                  onConflict: 'id',
                );
            break;
          case 'delete_category':
            await _client
                .from('categories')
                .delete()
                .eq('id', mutation.payload['category_id'])
                .eq('tenant_id', mutation.payload['tenant_id'])
                .eq('branch_id', mutation.payload['branch_id']);
            break;
          case 'select_branch':
            await _client
                .from('users')
                .update({'branch_id': mutation.payload['branch_id']})
                .eq('id', mutation.payload['user_id']);
            break;
          default:
            remaining.add(mutation);
        }
      } catch (_) {
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutations(userId, remaining);
  }

  Future<void> _syncUpsertProduct(Map<String, dynamic> payload) async {
    final product = Map<String, dynamic>.from(payload['product'] as Map);
    final stock = product.remove('stock') as int? ?? 0;
    product.remove('category_name');

    await _client.from('products').upsert(product, onConflict: 'id');
    await _client.from('inventory').upsert({
      'branch_id': product['branch_id'],
      'product_id': product['id'],
      'quantity': stock < 0 ? 0 : stock,
    }, onConflict: 'branch_id,product_id');
  }
}
