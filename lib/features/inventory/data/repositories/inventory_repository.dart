import 'dart:async';

import 'package:mobileshop_saas/core/extensions/product_sort_ext.dart';
import 'package:flutter/rendering.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/adjustment_extention.dart';
import 'package:mobileshop_saas/features/inventory/data/models/category_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/csv_import_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/price_history_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/stock_adjustment_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class InventoryRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);
  final SupabaseClient _client = Supabase.instance.client;

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  // Branch-level threshold update karo
  Future<void> updateBranchThreshold({
    required String productId,
    required int threshold,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final updatedAt = DateTime.now().toIso8601String();

    await _updateCachedBranchThreshold(
      branchId: branchId,
      productId: productId,
      threshold: threshold,
    );

    try {
      await _client
          .from('inventory')
          .upsert({
            'branch_id': branchId,
            'product_id': productId,
            'reorder_threshold': threshold,
            'updated_at': updatedAt,
          }, onConflict: 'branch_id,product_id')
          .timeout(_networkTimeout);
    } catch (_) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'branch_threshold',
        payload: {
          'branch_id': branchId,
          'product_id': productId,
          'threshold': threshold,
          'updated_at': updatedAt,
        },
      );
    }
  }

  // Category default threshold update karo
  Future<void> updateCategoryThreshold({
    required String categoryId,
    required int threshold,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    await _updateCachedCategoryThreshold(
      branchId: branchId,
      categoryId: categoryId,
      threshold: threshold,
    );

    try {
      await _client
          .from('categories')
          .update({'default_reorder_threshold': threshold})
          .eq('id', categoryId)
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .timeout(_networkTimeout);
    } catch (_) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'category_threshold',
        payload: {
          'tenant_id': tenantId,
          'branch_id': branchId,
          'category_id': categoryId,
          'threshold': threshold,
        },
      );
    }
  }

  Future<void> adjustStock({
    required String productId,
    required AdjustmentType type,
    required int quantity,
    required AdjustmentReason reason,
    String? reasonNote,
    bool isOverride = false,
    required ProductModel product,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final user = _currentUser;

    try {
      final invRow = await _client
          .from('inventory')
          .select('quantity')
          .eq('branch_id', branchId)
          .eq('product_id', productId)
          .maybeSingle()
          .timeout(_networkTimeout);

      final currentStock = (invRow?['quantity'] as num?)?.toInt() ?? 0;
      final newStock =
          type == AdjustmentType.stockIn
              ? currentStock + quantity
              : currentStock - quantity;

      if (newStock < 0 && !isOverride) {
        throw Exception(
          'Stock zero se neeche nahi ja sakta. '
          'Current stock: $currentStock, '
          'Requested: $quantity',
        );
      }

      final productRow = await _client
          .from('products')
          .select('cost_price')
          .eq('id', productId)
          .maybeSingle()
          .timeout(_networkTimeout);

      final unitCost =
          (productRow?['cost_price'] as num?)?.toDouble() ?? product.costPrice;
      final adjustment = _stockAdjustmentMap(
        id: const Uuid().v4(),
        tenantId: tenantId,
        branchId: branchId,
        product: product,
        type: type,
        quantity: quantity,
        reason: reason,
        userId: user.id,
        reasonNote: reasonNote,
        isOverride: isOverride,
        unitCost: unitCost,
        createdAt: DateTime.now(),
      );

      await _client
          .from('stock_adjustments')
          .insert(_remoteStockAdjustmentMap(adjustment))
          .timeout(_networkTimeout);

      await _client
          .from('inventory')
          .upsert({
            'branch_id': branchId,
            'product_id': productId,
            'quantity': newStock,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'branch_id,product_id')
          .timeout(_networkTimeout);

      await _checkAndNotifyHighValue(
        tenantId: tenantId,
        quantity: quantity,
        totalValue: unitCost * quantity,
        productId: productId,
      );

      await OfflineStore.upsertStockAdjustment(branchId, adjustment);
      await _cacheProductWithStock(
        product: product,
        tenantId: tenantId,
        branchId: branchId,
        stock: newStock,
      );
    } catch (e) {
      if (e.toString().contains('Stock zero se neeche')) rethrow;

      final currentStock = product.stock;
      final newStock =
          type == AdjustmentType.stockIn
              ? currentStock + quantity
              : currentStock - quantity;

      if (newStock < 0 && !isOverride) {
        throw Exception(
          'Stock zero se neeche nahi ja sakta. '
          'Current stock: $currentStock, '
          'Requested: $quantity',
        );
      }

      final adjustment = _stockAdjustmentMap(
        id: const Uuid().v4(),
        tenantId: tenantId,
        branchId: branchId,
        product: product,
        type: type,
        quantity: quantity,
        reason: reason,
        userId: user.id,
        reasonNote: reasonNote,
        isOverride: isOverride,
        unitCost: product.costPrice,
        createdAt: DateTime.now(),
      );

      await OfflineStore.upsertStockAdjustment(branchId, adjustment);
      await _cacheProductWithStock(
        product: product,
        tenantId: tenantId,
        branchId: branchId,
        stock: newStock,
      );
      await OfflineStore.enqueueMutation(
        userId: user.id,
        type: 'stock_adjustment',
        payload: {'adjustment': adjustment, 'new_stock': newStock},
      );
      debugPrint('Error occurred while adjusting stock: $e');
    }
  }

  Future<List<StockAdjustmentModel>> getAdjustments({
    String? productId,
    int limit = 50,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);

    var query = _client
        .from('stock_adjustments')
        .select('*, products(name)')
        .eq('branch_id', branchId);

    if (productId != null) {
      query = query.eq('product_id', productId);
    }

    final data = await query
        .order('created_at', ascending: false)
        .limit(limit)
        .timeout(_networkTimeout);

    return (data as List).map((e) => StockAdjustmentModel.fromMap(e)).toList();
  }

  Future<void> _checkAndNotifyHighValue({
    required String tenantId,
    required int quantity,
    required double totalValue,
    required String productId,
  }) async {
    final settings = await getSettings();

    // Agar settings nahi hain → defaults use karo
    final qtyThreshold =
        (settings['adjustment_qty_threshold'] as num?)?.toInt() ?? 10;
    final valueThreshold =
        (settings['adjustment_value_threshold'] as num?)?.toDouble() ?? 50000;

    // Check karo → threshold cross hua?
    final isHighQty = quantity >= qtyThreshold;
    final isHighValue = totalValue >= valueThreshold;

    if (isHighQty || isHighValue) {
      // Abhi sirf log karo → baad mein SMS/push add karein ge
      debugPrint(
        '⚠️ HIGH VALUE ADJUSTMENT: '
        'qty=$quantity (threshold=$qtyThreshold), '
        'value=$totalValue (threshold=$valueThreshold)',
      );

      // Future: yahan SMS ya push notification bhejein ge
      // NotificationService.notifyOwner(...)
    }
  }

  Future<Map<String, dynamic>> getSettings() async {
    final tenantId = await _currentTenantId();

    try {
      final settings = await _client
          .from('tenant_settings')
          .select()
          .eq('tenant_id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);

      // Agar settings nahi hain → defaults return karo
      final resolved = settings ?? _defaultSettings(tenantId);
      await OfflineStore.saveTenantSettings(tenantId, resolved);
      return resolved;
    } catch (_) {
      return await OfflineStore.loadTenantSettings(tenantId) ??
          _defaultSettings(tenantId);
    }
  }

  Future<void> saveSettings({
    required int qtyThreshold,
    required double valueThreshold,
  }) async {
    final tenantId = await _currentTenantId();
    final settings = {
      'tenant_id': tenantId,
      'adjustment_qty_threshold': qtyThreshold,
      'adjustment_value_threshold': valueThreshold,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await OfflineStore.saveTenantSettings(tenantId, settings);

    try {
      await _client
          .from('tenant_settings')
          .upsert(settings, onConflict: 'tenant_id')
          .timeout(_networkTimeout);
    } catch (_) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'tenant_settings',
        payload: {'settings': settings},
      );
    }
  }

  Future<Map<String, dynamic>> _currentProfile() async {
    final cachedProfile = await OfflineStore.loadProfile(_currentUser.id);
    if (cachedProfile != null) {
      unawaited(_refreshProfileCache());
      return cachedProfile;
    }

    Map<String, dynamic>? profile;
    try {
      profile = await _remoteProfile().timeout(_networkTimeout);
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

  Future<Map<String, dynamic>?> _remoteProfile() {
    return _client
        .from('users')
        .select('id, tenant_id, branch_id, full_name, email, phone, role')
        .eq('id', _currentUser.id)
        .maybeSingle();
  }

  Future<void> _refreshProfileCache() async {
    try {
      final profile = await _remoteProfile().timeout(_networkTimeout);
      if (profile != null) {
        final selectedBranchId = await OfflineStore.loadSelectedBranchId(
          _currentUser.id,
        );
        if (selectedBranchId != null) {
          profile['branch_id'] = selectedBranchId;
        }
        await OfflineStore.saveProfile(_currentUser.id, profile);
      }
    } catch (_) {}
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
    if (selectedBranchId != null &&
        await _branchBelongsToTenant(
          tenantId: tenantId,
          branchId: selectedBranchId,
        )) {
      return selectedBranchId;
    }

    final cachedBranches = await OfflineStore.loadBranches(tenantId);
    if (cachedBranches.isNotEmpty && cachedBranches.first.id != null) {
      return cachedBranches.first.id!;
    }

    final branch = await _client
        .from('branches')
        .select('id')
        .eq('tenant_id', tenantId)
        .order('id')
        .limit(1)
        .maybeSingle()
        .timeout(_networkTimeout);

    final branchId = branch?['id'] as String?;
    if (branchId == null) throw Exception('Branch not found');
    return branchId;
  }

  // ── Products ──
  Future<bool> _branchBelongsToTenant({
    required String tenantId,
    required String branchId,
  }) async {
    final cachedBranches = await OfflineStore.loadBranches(tenantId);
    if (cachedBranches.any((branch) => branch.id == branchId)) return true;

    try {
      final branch = await _client
          .from('branches')
          .select('id')
          .eq('id', branchId)
          .eq('tenant_id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);
      return branch != null;
    } catch (_) {
      return false;
    }
  }

  Future<List<ProductModel>> fetchProducts({String? categoryId}) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final cachedProducts = await OfflineStore.loadProducts(branchId);
    if (cachedProducts.isNotEmpty) {
      unawaited(syncOfflineMutations());
      unawaited(
        _refreshProductsCache(branchId: branchId, categoryId: categoryId),
      );
      if (categoryId == null) return cachedProducts;
      return cachedProducts
          .where((product) => product.categoryId == categoryId)
          .toList();
    }

    try {
      return await _fetchRemoteProducts(
        tenantId: tenantId,
        branchId: branchId,
        categoryId: categoryId,
      ).timeout(_networkTimeout);
    } catch (_) {
      final products = await OfflineStore.loadProducts(branchId);
      if (categoryId == null) return products;
      return products
          .where((product) => product.categoryId == categoryId)
          .toList();
    }
  }

  Future<List<ProductModel>> _fetchRemoteProducts({
    required String tenantId,
    required String branchId,
    String? categoryId,
    String? queryText,
    ProductSortOption sortOption = ProductSortOption.nameAZ,
    int? limit,
    int offset = 0,
  }) async {
    var query = _client
        .from('products')
        .select(
          '*, categories(name, default_reorder_threshold), inventory!inner(quantity, reorder_threshold, branch_id)',
        )
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId)
        .eq('inventory.branch_id', branchId)
        .eq('is_active', true);

    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }

    final normalizedQuery = queryText?.trim();
    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      final escaped = _escapePostgrestPattern(normalizedQuery);
      query = query.or('name.ilike.$escaped%,sku.ilike.$escaped%');
    }

    var ordered = _orderProducts(query, sortOption);
    if (limit != null) {
      final safeLimit = limit.clamp(1, 100).toInt();
      final safeOffset = offset < 0 ? 0 : offset;
      ordered = ordered.range(safeOffset, safeOffset + safeLimit - 1);
    }

    final data = await ordered;
    final products =
        (data as List).map((e) => ProductModel.fromMap(e)).toList();
    if (categoryId == null && normalizedQuery?.isNotEmpty != true) {
      await OfflineStore.saveProducts(branchId, products);
    } else {
      for (final product in products) {
        await OfflineStore.upsertCachedProduct(product);
      }
    }
    return products;
  }

  dynamic _orderProducts(dynamic query, ProductSortOption sortOption) {
    switch (sortOption) {
      case ProductSortOption.nameAZ:
        return query.order('name', ascending: true);
      case ProductSortOption.nameZA:
        return query.order('name');
      case ProductSortOption.priceLow:
        return query
            .order('sale_price', ascending: true)
            .order('name', ascending: true);
      case ProductSortOption.priceHigh:
        return query.order('sale_price').order('name', ascending: true);
      case ProductSortOption.stockLow:
        return query
            .order('quantity', referencedTable: 'inventory', ascending: true)
            .order('name', ascending: true);
      case ProductSortOption.stockHigh:
        return query
            .order('quantity', referencedTable: 'inventory')
            .order('name', ascending: true);
    }
  }

  Future<List<ProductModel>> searchProducts({
    required String query,
    String? categoryId,
    ProductSortOption sortOption = ProductSortOption.nameAZ,
    int limit = 50,
    int offset = 0,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final normalizedQuery = query.trim();

    final localProducts = await OfflineStore.searchProducts(
      branchId: branchId,
      query: normalizedQuery,
      categoryId: categoryId,
      sortOption: sortOption,
      limit: limit,
      offset: offset,
    );
    if (localProducts.isNotEmpty) {
      unawaited(syncOfflineMutations());
      return localProducts;
    }

    try {
      return await _fetchRemoteProducts(
        tenantId: tenantId,
        branchId: branchId,
        categoryId: categoryId,
        queryText: normalizedQuery,
        sortOption: sortOption,
        limit: limit,
        offset: offset,
      ).timeout(_networkTimeout);
    } catch (_) {
      return localProducts;
    }
  }

  Future<void> _refreshProductsCache({
    required String branchId,
    String? categoryId,
  }) async {
    try {
      final tenantId = await _currentTenantId();
      await _fetchRemoteProducts(
        tenantId: tenantId,
        branchId: branchId,
        categoryId: categoryId,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<ProductModel> addProduct(ProductModel product) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data = await _client
          .from('products')
          .insert(product.toInsertMap(tenantId: tenantId, branchId: branchId))
          .select('id')
          .single()
          .timeout(_networkTimeout);

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
          .eq('tenant_id', tenantId)
          .timeout(_networkTimeout);

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
      final data = await _client
          .from('products')
          .select('*, categories(name), inventory!inner(quantity, branch_id)')
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .eq('inventory.branch_id', branchId)
          .eq('id', productId)
          .single()
          .timeout(_networkTimeout);

      final product = ProductModel.fromMap(data);
      await OfflineStore.upsertCachedProduct(product);
      return product;
    } catch (_) {
      final products = await OfflineStore.loadProducts(branchId);
      return products.firstWhere((product) => product.id == productId);
    }
  }

  Future<StockAdjustmentModel> fetchAdjustedProducts(String productId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    try {
      final data = await _client
          .from('stock_adjustments')
          .select('*, products(name)')
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .eq('product_id', productId)
          .order('created_at', ascending: false)
          .limit(1)
          .single()
          .timeout(_networkTimeout);

      return StockAdjustmentModel.fromMap(data);
    } catch (_) {
      throw Exception('No stock adjustments found for product $productId');
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
          .eq('branch_id', branchId)
          .timeout(_networkTimeout);
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

  Future<CsvImportResult> importFromCsv(
    List<List<dynamic>> csvRows, {
    void Function(CsvImportProgress progress)? onProgress,
    int batchSize = 500,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final userId = _currentUser.id;
    final safeBatchSize = batchSize.clamp(100, 1000).toInt();
    final dataRows = csvRows.skip(1).toList();

    final results = <CsvRowResult>[];
    final importedSkus = <String>{};
    var categoriesChanged = false;
    var successCount = 0;
    var failedCount = 0;

    final cachedProducts = await OfflineStore.loadProducts(branchId);
    final existingSkus = <String>{
      for (final product in cachedProducts)
        if (product.sku != null && product.sku!.trim().isNotEmpty)
          product.sku!.trim().toLowerCase(),
    };
    final categoryByName = <String, CategoryModel>{
      for (final category in await OfflineStore.loadCategories(branchId))
        category.name.trim().toLowerCase(): category,
    };
    final totalBatches =
        dataRows.isEmpty ? 0 : ((dataRows.length - 1) ~/ safeBatchSize) + 1;

    void emitProgress(int processedRows, int currentBatch, String message) {
      onProgress?.call(
        CsvImportProgress(
          totalRows: dataRows.length,
          processedRows: processedRows,
          successCount: successCount,
          failedCount: failedCount,
          currentBatch: currentBatch,
          totalBatches: totalBatches,
          message: message,
        ),
      );
    }

    emitProgress(0, 0, 'Import prepare ho raha hai...');

    for (
      var batchStart = 0;
      batchStart < dataRows.length;
      batchStart += safeBatchSize
    ) {
      final batchEnd =
          (batchStart + safeBatchSize) > dataRows.length
              ? dataRows.length
              : batchStart + safeBatchSize;
      final batchRows = dataRows.sublist(batchStart, batchEnd);
      final currentBatch = (batchStart ~/ safeBatchSize) + 1;
      final batchProducts = <ProductModel>[];
      final batchSkuCandidates = <String>{
        for (final row in batchRows)
          if (_cell(row, 1).trim().isNotEmpty) _cell(row, 1).trim(),
      };
      final remoteExistingSkus = await _existingSkusInRemoteBatch(
        branchId: branchId,
        skus: batchSkuCandidates,
      );

      for (int i = 0; i < batchRows.length; i++) {
        final row = batchRows[i];
        final rowNum = batchStart + i + 2;
        final name = _cell(row, 0);
        final sku = _cell(row, 1);
        final salePriceStr = _cell(row, 2);
        final costPriceStr = _cell(row, 3);
        final categoryName = _cell(row, 4);
        final quantityStr = _cell(row, 5);

        if (name.isEmpty) {
          results.add(
            CsvRowResult(
              rowNumber: rowNum,
              isSuccess: false,
              errorReason: 'Name is empty',
            ),
          );
          failedCount++;
          continue;
        }

        final salePrice = double.tryParse(salePriceStr);
        if (salePrice == null || salePrice < 0) {
          results.add(
            CsvRowResult(
              rowNumber: rowNum,
              name: name,
              sku: sku,
              isSuccess: false,
              errorReason: 'Sale price is not a valid number: "$salePriceStr"',
            ),
          );
          failedCount++;
          continue;
        }

        final normalizedSku = sku.toLowerCase();
        if (normalizedSku.isNotEmpty && importedSkus.contains(normalizedSku)) {
          results.add(
            CsvRowResult(
              rowNumber: rowNum,
              name: name,
              sku: sku,
              isSuccess: false,
              errorReason: 'SKU already exists in CSV: "$sku"',
            ),
          );
          failedCount++;
          continue;
        }

        if (normalizedSku.isNotEmpty &&
            (existingSkus.contains(normalizedSku) ||
                remoteExistingSkus.contains(normalizedSku))) {
          results.add(
            CsvRowResult(
              rowNumber: rowNum,
              name: name,
              sku: sku,
              isSuccess: false,
              errorReason: 'SKU already exists: "$sku"',
            ),
          );
          failedCount++;
          continue;
        }

        CategoryModel? category;
        if (categoryName.isNotEmpty) {
          final categoryKey = categoryName.trim().toLowerCase();
          category = categoryByName[categoryKey];
          if (category == null) {
            category = await _findOrCreateCsvCategory(
              name: categoryName,
              tenantId: tenantId,
              branchId: branchId,
              userId: userId,
            );
            categoryByName[categoryKey] = category;
            categoriesChanged = true;
          }
        }

        final costPrice = double.tryParse(costPriceStr) ?? 0;
        final quantity = int.tryParse(quantityStr) ?? 0;
        final product = ProductModel(
          id: const Uuid().v4(),
          tenantId: tenantId,
          branchId: branchId,
          categoryId: category?.id,
          categoryName: category?.name,
          name: name,
          sku: sku.isEmpty ? null : sku,
          salePrice: salePrice,
          costPrice: costPrice,
          isActive: true,
          stock: quantity < 0 ? 0 : quantity,
          categoryThreshold: category?.defaultReorderThreshold ?? 0,
        );

        batchProducts.add(product);
        if (normalizedSku.isNotEmpty) {
          importedSkus.add(normalizedSku);
          existingSkus.add(normalizedSku);
        }
        successCount++;
        results.add(
          CsvRowResult(
            rowNumber: rowNum,
            name: name,
            sku: sku,
            isSuccess: true,
          ),
        );
      }

      if (batchProducts.isNotEmpty) {
        await _upsertCsvProductBatch(
          tenantId: tenantId,
          branchId: branchId,
          userId: userId,
          products: batchProducts,
        );
        await OfflineStore.upsertCachedProductsBatch(branchId, batchProducts);
      }

      emitProgress(
        batchEnd,
        currentBatch,
        'Batch $currentBatch / $totalBatches imported',
      );
    }

    if (categoriesChanged) {
      try {
        await _fetchRemoteCategories(
          tenantId: tenantId,
          branchId: branchId,
        ).timeout(_networkTimeout);
      } catch (_) {}
    }

    return CsvImportResult(
      totalRows: dataRows.length,
      successCount: successCount,
      failedCount: failedCount,
      rows: results,
    );
  }

  // ignore: unused_element
  Future<CsvImportResult> _importFromCsvLegacy(
    List<List<dynamic>> csvRows,
  ) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final userId = _currentUser.id;

    // Row 0 = headers → skip karo
    final dataRows = csvRows.skip(1).toList();

    final results = <CsvRowResult>[];
    final importedSkus = <String>{}; // is import mein duplicate check
    var productsChanged = false;
    var categoriesChanged = false;

    for (int i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      final rowNum = i + 2; // +2 kyunki row 1 = header, row 2 = pehla data

      // ── Column values nikalo ──
      final name = _cell(row, 0); // column A
      final sku = _cell(row, 1); // column B
      final salePriceStr = _cell(row, 2); // column C
      final costPriceStr = _cell(row, 3); // column D
      final categoryName = _cell(row, 4); // column E
      final quantityStr = _cell(row, 5); // column F

      // ── Validation ──

      // 1. Name required
      if (name.isEmpty) {
        results.add(
          CsvRowResult(
            rowNumber: rowNum,
            isSuccess: false,
            errorReason: 'Name is empty',
          ),
        );
        continue; // next row pe jao
      }

      // 2. Sale price valid number hona chahiye
      final salePrice = double.tryParse(salePriceStr);
      if (salePrice == null || salePrice < 0) {
        results.add(
          CsvRowResult(
            rowNumber: rowNum,
            name: name,
            sku: sku,
            isSuccess: false,
            errorReason: 'Sale price is not a valid number: "$salePriceStr"',
          ),
        );
        continue;
      }

      // 3. SKU duplicate check (is CSV mein)
      final normalizedSku = sku.toLowerCase();
      if (normalizedSku.isNotEmpty && importedSkus.contains(normalizedSku)) {
        results.add(
          CsvRowResult(
            rowNumber: rowNum,
            name: name,
            sku: sku,
            isSuccess: false,
            errorReason: 'SKU already exists in CSV: "$sku"',
          ),
        );
        continue;
      }

      // 4. SKU duplicate check (DB mein already exist karta hai?)
      if (sku.isNotEmpty && await _skuExists(branchId: branchId, sku: sku)) {
        results.add(
          CsvRowResult(
            rowNumber: rowNum,
            name: name,
            sku: sku,
            isSuccess: false,
            errorReason: 'SKU already exists: "$sku"',
          ),
        );
        continue;
      }

      // ── Valid row → save karo ──

      // Category handle karo (naam se find ya create)
      CategoryModel? category;
      if (categoryName.isNotEmpty) {
        category = await _findOrCreateCsvCategory(
          name: categoryName,
          tenantId: tenantId,
          branchId: branchId,
          userId: userId,
        );
        categoriesChanged = true;
      }

      // Product insert karo
      final costPrice = double.tryParse(costPriceStr) ?? 0;
      final quantity = int.tryParse(quantityStr) ?? 0;
      final product = ProductModel(
        id: const Uuid().v4(),
        tenantId: tenantId,
        branchId: branchId,
        categoryId: category?.id,
        categoryName: category?.name,
        name: name,
        sku: sku.isEmpty ? null : sku,
        salePrice: salePrice,
        costPrice: costPrice,
        isActive: true,
        stock: quantity < 0 ? 0 : quantity,
        categoryThreshold: category?.defaultReorderThreshold ?? 0,
      );

      try {
        await _client
            .from('products')
            .upsert({
              'id': product.id,
              ...product.toInsertMap(tenantId: tenantId, branchId: branchId),
            }, onConflict: 'id')
            .timeout(_networkTimeout);

        // Inventory row banao
        await _client
            .from('inventory')
            .upsert({
              'branch_id': branchId,
              'product_id': product.id,
              'quantity': product.stock,
              'updated_at': DateTime.now().toIso8601String(),
            }, onConflict: 'branch_id,product_id')
            .timeout(_networkTimeout);
      } catch (_) {
        await OfflineStore.enqueueMutation(
          userId: userId,
          type: 'upsert_product',
          payload: {'product': product.toCacheMap()},
        );
      }

      await OfflineStore.upsertCachedProduct(product);

      // SKU track karo (duplicate check ke liye)
      if (normalizedSku.isNotEmpty) importedSkus.add(normalizedSku);
      productsChanged = true;

      results.add(
        CsvRowResult(rowNumber: rowNum, name: name, sku: sku, isSuccess: true),
      );
    }

    if (categoriesChanged) {
      try {
        await _fetchRemoteCategories(
          tenantId: tenantId,
          branchId: branchId,
        ).timeout(_networkTimeout);
      } catch (_) {}
    }

    if (productsChanged) {
      try {
        await _fetchRemoteProducts(
          tenantId: tenantId,
          branchId: branchId,
        ).timeout(_networkTimeout);
      } catch (_) {}
    }

    return CsvImportResult(
      totalRows: dataRows.length,
      successCount: results.where((r) => r.isSuccess).length,
      failedCount: results.where((r) => !r.isSuccess).length,
      rows: results,
    );
  }

  Future<Set<String>> _existingSkusInRemoteBatch({
    required String branchId,
    required Set<String> skus,
  }) async {
    if (skus.isEmpty) return const <String>{};
    try {
      final rows = await _client
          .from('products')
          .select('sku')
          .eq('branch_id', branchId)
          .inFilter('sku', skus.toList())
          .timeout(_networkTimeout);
      return {
        for (final row in rows as List)
          if ((row as Map)['sku'] != null)
            row['sku'].toString().trim().toLowerCase(),
      };
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> _upsertCsvProductBatch({
    required String tenantId,
    required String branchId,
    required String userId,
    required List<ProductModel> products,
  }) async {
    try {
      await _client
          .from('products')
          .upsert(
            products
                .map(
                  (product) => {
                    'id': product.id,
                    ...product.toInsertMap(
                      tenantId: tenantId,
                      branchId: branchId,
                    ),
                  },
                )
                .toList(),
            onConflict: 'id',
          )
          .timeout(_networkTimeout);

      final updatedAt = DateTime.now().toIso8601String();
      await _client
          .from('inventory')
          .upsert(
            products
                .map(
                  (product) => {
                    'branch_id': branchId,
                    'product_id': product.id,
                    'quantity': product.stock,
                    'updated_at': updatedAt,
                  },
                )
                .toList(),
            onConflict: 'branch_id,product_id',
          )
          .timeout(_networkTimeout);
    } catch (_) {
      for (final product in products) {
        await OfflineStore.enqueueMutation(
          userId: userId,
          type: 'upsert_product',
          payload: {'product': product.toCacheMap()},
        );
      }
    }
  }

  // Helper: CSV cell safe nikalo
  String _cell(List<dynamic> row, int index) {
    if (index >= row.length) return '';
    return row[index]?.toString().trim() ?? '';
  }

  Future<bool> _skuExists({
    required String branchId,
    required String sku,
  }) async {
    final cachedProducts = await OfflineStore.loadProducts(branchId);
    final normalizedSku = sku.toLowerCase();
    final existsInCache = cachedProducts.any(
      (product) => product.sku?.toLowerCase() == normalizedSku,
    );
    if (existsInCache) return true;

    try {
      final existing = await _client
          .from('products')
          .select('id')
          .eq('branch_id', branchId)
          .eq('sku', sku)
          .maybeSingle()
          .timeout(_networkTimeout);
      return existing != null;
    } catch (_) {
      return false;
    }
  }

  // Helper: Category naam se find karo ya create karo
  // ignore: unused_element
  Future<String> _findOrCreateCategory({
    required String name,
    required String tenantId,
    required String branchId,
  }) async {
    // Pehle find karo
    final existing =
        await _client
            .from('categories')
            .select('id')
            .eq('branch_id', branchId)
            .eq('name', name)
            .maybeSingle();

    if (existing != null) return existing['id'] as String;

    // Nahi mila → create karo
    final created =
        await _client
            .from('categories')
            .insert({
              'tenant_id': tenantId,
              'branch_id': branchId,
              'name': name,
            })
            .select('id')
            .single();

    return created['id'] as String;
  }

  // ── Bulk Pricing / Price History / IMEI Guards ──
  Future<CategoryModel> _findOrCreateCsvCategory({
    required String name,
    required String tenantId,
    required String branchId,
    required String userId,
  }) async {
    final cachedCategories = await OfflineStore.loadCategories(branchId);
    for (final category in cachedCategories) {
      if (category.name.toLowerCase() == name.toLowerCase()) {
        return category;
      }
    }

    try {
      final existing = await _client
          .from('categories')
          .select()
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .eq('name', name)
          .maybeSingle()
          .timeout(_networkTimeout);

      if (existing != null) {
        final category = CategoryModel.fromMap(existing);
        await _upsertCachedCategory(branchId, category);
        return category;
      }
    } catch (_) {}

    final category = CategoryModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      name: name,
    );

    await _upsertCachedCategory(branchId, category);

    try {
      final created = await _client
          .from('categories')
          .upsert(category.toCacheMap(), onConflict: 'id')
          .select()
          .single()
          .timeout(_networkTimeout);
      final savedCategory = CategoryModel.fromMap(created);
      await _upsertCachedCategory(branchId, savedCategory);
      return savedCategory;
    } catch (_) {
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'upsert_category',
        payload: {'category': category.toCacheMap()},
      );
      return category;
    }
  }

  Future<void> _upsertCachedCategory(
    String branchId,
    CategoryModel category,
  ) async {
    final categories = await OfflineStore.loadCategories(branchId);
    await OfflineStore.saveCategories(
      branchId,
      [...categories.where((item) => item.id != category.id), category]
        ..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  Future<int> bulkUpdateProductPrices({
    required List<ProductModel> products,
    required double percentage,
    required String direction,
  }) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final branchProducts =
        products
            .where(
              (product) =>
                  product.branchId == branchId &&
                  (product.tenantId.isEmpty || product.tenantId == tenantId),
            )
            .toList();
    if (branchProducts.isEmpty) return 0;
    return _bulkUpdateProductPricesDirectly(
      products: branchProducts,
      percentage: percentage,
      direction: direction,
    );
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
        reorderThreshold: product.reorderThreshold,
        branchThreshold: product.branchThreshold,
        categoryThreshold: product.categoryThreshold,
      );

      try {
        final updatedRows = await _client
            .from('products')
            .update({'sale_price': newPrice})
            .eq('id', product.id)
            .eq('branch_id', branchId)
            .eq('tenant_id', tenantId)
            .eq('is_active', true)
            .select('id')
            .timeout(_networkTimeout);

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
    try {
      final tenantId = await _currentTenantId();
      final branchId = await _currentBranchId(tenantId);
      final data = await _client
          .from('product_price_history')
          .select()
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .eq('product_id', productId)
          .order('changed_at', ascending: false)
          .limit(50)
          .timeout(_networkTimeout);

      return (data as List).map((e) => PriceHistoryModel.fromMap(e)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> productHasActiveImeiUnits(String productId) async {
    try {
      await fetchProduct(productId);
      final hasUnits = await _client
          .rpc(
            'product_has_active_imei_units',
            params: {'p_product_id': productId},
          )
          .timeout(_networkTimeout);

      return hasUnits == true;
    } catch (_) {
      return false;
    }
  }

  // ── Categories ──
  Future<List<CategoryModel>> fetchCategories() async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final cachedCategories = await OfflineStore.loadCategories(branchId);
    if (cachedCategories.isNotEmpty) {
      unawaited(syncOfflineMutations());
      unawaited(
        _refreshCategoriesCache(tenantId: tenantId, branchId: branchId),
      );
      return cachedCategories;
    }

    try {
      return await _fetchRemoteCategories(
        tenantId: tenantId,
        branchId: branchId,
      ).timeout(_networkTimeout);
    } catch (_) {
      return OfflineStore.loadCategories(branchId);
    }
  }

  Future<List<CategoryModel>> _fetchRemoteCategories({
    required String tenantId,
    required String branchId,
  }) async {
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
  }

  Future<void> _refreshCategoriesCache({
    required String tenantId,
    required String branchId,
  }) async {
    try {
      await _fetchRemoteCategories(
        tenantId: tenantId,
        branchId: branchId,
      ).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<CategoryModel> addCategory(String name) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final category = CategoryModel(
      id: const Uuid().v4(),
      tenantId: tenantId,
      branchId: branchId,
      name: name,
    );
    try {
      final data = await _client
          .from('categories')
          .insert(category.toCacheMap())
          .select()
          .single()
          .timeout(_networkTimeout);

      final savedCategory = CategoryModel.fromMap(data);
      final categories = await OfflineStore.loadCategories(branchId);
      await OfflineStore.saveCategories(
        branchId,
        [
          ...categories.where((item) => item.id != savedCategory.id),
          savedCategory,
        ]..sort((a, b) => a.name.compareTo(b.name)),
      );
      return savedCategory;
    } catch (_) {
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
          .eq('branch_id', branchId)
          .timeout(_networkTimeout);
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

  Future<void> setStock({
    required String productId,
    required String branchId,
    required int quantity,
  }) async {
    await _client
        .from('inventory')
        .upsert({
          'branch_id': branchId,
          'product_id': productId,
          'quantity': quantity < 0 ? 0 : quantity,
        }, onConflict: 'branch_id,product_id')
        .timeout(_networkTimeout);
  }

  Future<int> getStock({
    required String productId,
    required String branchId,
  }) async {
    final data = await _client
        .from('inventory')
        .select('quantity')
        .eq('product_id', productId)
        .eq('branch_id', branchId)
        .maybeSingle()
        .timeout(_networkTimeout);

    return (data?['quantity'] as num?)?.toInt() ?? 0;
  }

  Map<String, dynamic> _defaultSettings(String tenantId) => {
    'tenant_id': tenantId,
    'adjustment_qty_threshold': 10,
    'adjustment_value_threshold': 50000.0,
    'updated_at': DateTime.now().toIso8601String(),
  };

  String _escapePostgrestPattern(String value) {
    return value
        .replaceAll(',', ' ')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  Map<String, dynamic> _stockAdjustmentMap({
    required String id,
    required String tenantId,
    required String branchId,
    required ProductModel product,
    required AdjustmentType type,
    required int quantity,
    required AdjustmentReason reason,
    required String userId,
    required double unitCost,
    required DateTime createdAt,
    String? reasonNote,
    bool isOverride = false,
  }) {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'product_id': product.id,
      'product_name': product.name,
      'adjustment_type': type.label,
      'quantity': quantity,
      'reason': reason.label,
      'adjusted_by': userId,
      'created_at': createdAt.toIso8601String(),
      'user_id': userId,
      'reason_code': reason.code,
      'reason_note': reasonNote,
      'is_override': isOverride,
      'unit_cost': unitCost,
      'total_value': unitCost * quantity,
    };
  }

  Map<String, dynamic> _remoteStockAdjustmentMap(
    Map<String, dynamic> adjustment,
  ) {
    final remote = Map<String, dynamic>.from(adjustment);
    remote.remove('product_name');
    remote.remove('products');
    return remote;
  }

  Future<void> _cacheProductWithStock({
    required ProductModel product,
    required String tenantId,
    required String branchId,
    required int stock,
  }) async {
    final cachedProduct = ProductModel(
      id: product.id,
      tenantId: product.tenantId.isEmpty ? tenantId : product.tenantId,
      branchId: product.branchId.isEmpty ? branchId : product.branchId,
      categoryId: product.categoryId,
      categoryName: product.categoryName,
      name: product.name,
      sku: product.sku,
      description: product.description,
      salePrice: product.salePrice,
      costPrice: product.costPrice,
      imeiTracked: product.imeiTracked,
      isActive: product.isActive,
      stock: stock,
      reorderThreshold: product.reorderThreshold,
      branchThreshold: product.branchThreshold,
      categoryThreshold: product.categoryThreshold,
    );
    await OfflineStore.upsertCachedProduct(cachedProduct);
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
      reorderThreshold: product.reorderThreshold,
      branchThreshold: product.branchThreshold,
      categoryThreshold: product.categoryThreshold,
    );
  }

  Future<void> _updateCachedBranchThreshold({
    required String branchId,
    required String productId,
    required int threshold,
  }) async {
    final products = await OfflineStore.loadProducts(branchId);
    if (products.isEmpty) return;

    await OfflineStore.saveProducts(branchId, [
      for (final product in products)
        if (product.id == productId)
          _copyProduct(product, branchThreshold: threshold)
        else
          product,
    ]);
  }

  Future<void> _updateCachedCategoryThreshold({
    required String branchId,
    required String categoryId,
    required int threshold,
  }) async {
    final categories = await OfflineStore.loadCategories(branchId);
    await OfflineStore.saveCategories(branchId, [
      for (final category in categories)
        if (category.id == categoryId)
          CategoryModel(
            id: category.id,
            tenantId: category.tenantId,
            branchId: category.branchId,
            name: category.name,
            defaultReorderThreshold: threshold,
          )
        else
          category,
    ]);

    final products = await OfflineStore.loadProducts(branchId);
    if (products.isEmpty) return;

    await OfflineStore.saveProducts(branchId, [
      for (final product in products)
        if (product.categoryId == categoryId)
          _copyProduct(product, categoryThreshold: threshold)
        else
          product,
    ]);
  }

  ProductModel _copyProduct(
    ProductModel product, {
    int? stock,
    int? reorderThreshold,
    int? branchThreshold,
    int? categoryThreshold,
  }) {
    return ProductModel(
      id: product.id,
      tenantId: product.tenantId,
      branchId: product.branchId,
      categoryId: product.categoryId,
      categoryName: product.categoryName,
      name: product.name,
      sku: product.sku,
      description: product.description,
      salePrice: product.salePrice,
      costPrice: product.costPrice,
      imeiTracked: product.imeiTracked,
      isActive: product.isActive,
      stock: stock ?? product.stock,
      reorderThreshold: reorderThreshold ?? product.reorderThreshold,
      branchThreshold: branchThreshold ?? product.branchThreshold,
      categoryThreshold: categoryThreshold ?? product.categoryThreshold,
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
          case 'branch_threshold':
            await _client.from('inventory').upsert({
              'branch_id': mutation.payload['branch_id'],
              'product_id': mutation.payload['product_id'],
              'reorder_threshold': mutation.payload['threshold'],
              'updated_at': mutation.payload['updated_at'],
            }, onConflict: 'branch_id,product_id');
            break;
          case 'category_threshold':
            await _client
                .from('categories')
                .update({
                  'default_reorder_threshold': mutation.payload['threshold'],
                })
                .eq('id', mutation.payload['category_id'])
                .eq('tenant_id', mutation.payload['tenant_id'])
                .eq('branch_id', mutation.payload['branch_id']);
            break;
          case 'stock_adjustment':
            await _syncStockAdjustment(mutation.payload);
            break;
          case 'tenant_settings':
            await _syncTenantSettings(mutation.payload);
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
    product.remove('categories');
    product.remove('branch_threshold');
    product.remove('category_threshold');

    await _client.from('products').upsert(product, onConflict: 'id');
    await _client.from('inventory').upsert({
      'branch_id': product['branch_id'],
      'product_id': product['id'],
      'quantity': stock < 0 ? 0 : stock,
    }, onConflict: 'branch_id,product_id');
  }

  Future<void> _syncStockAdjustment(Map<String, dynamic> payload) async {
    final adjustment = Map<String, dynamic>.from(payload['adjustment'] as Map);
    final newStock = (payload['new_stock'] as num).toInt();

    await _client
        .from('stock_adjustments')
        .upsert(_remoteStockAdjustmentMap(adjustment), onConflict: 'id');
    await _client.from('inventory').upsert({
      'branch_id': adjustment['branch_id'],
      'product_id': adjustment['product_id'],
      'quantity': newStock,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'branch_id,product_id');
  }

  Future<void> _syncTenantSettings(Map<String, dynamic> payload) async {
    final settings = Map<String, dynamic>.from(payload['settings'] as Map);
    await _client
        .from('tenant_settings')
        .upsert(settings, onConflict: 'tenant_id');
  }
}
