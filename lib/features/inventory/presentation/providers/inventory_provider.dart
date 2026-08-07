import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/extensions/product_sort_ext.dart';
import 'package:mobileshop_saas/features/inventory/data/models/stock_adjustment_model.dart';

import '../../data/models/category_model.dart';
import '../../data/models/price_history_model.dart';
import '../../data/models/product_model.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../../onboarding/data/repositories/setup_flow_repository.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../domain/inventory_entitlement_gate.dart';

class BulkPriceUpdateRequest {
  final List<ProductModel> products;
  final double percentage;
  final String direction;

  const BulkPriceUpdateRequest({
    required this.products,
    required this.percentage,
    required this.direction,
  });

  List<String> get productIds => products.map((product) => product.id).toList();
}

final stockAdjustmentControllerProvider =
    StateNotifierProvider<StockAdjustmentController, AsyncValue<void>>((ref) {
      return StockAdjustmentController(
        ref.read(inventoryRepositoryProvider),
        ref,
      );
    });

final tenantSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.read(inventoryRepositoryProvider).getSettings();
});

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AsyncValue<void>>((ref) {
      return SettingsController(ref.read(inventoryRepositoryProvider), ref);
    });

class SettingsController extends StateNotifier<AsyncValue<void>> {
  final InventoryRepository _repository;
  final Ref _ref;

  SettingsController(this._repository, this._ref)
    : super(const AsyncData(null));

  Future<bool> saveSettings({
    required int qtyThreshold,
    required double valueThreshold,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.saveSettings(
        qtyThreshold: qtyThreshold,
        valueThreshold: valueThreshold,
      );
      _ref.invalidate(tenantSettingsProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

class StockAdjustmentController extends StateNotifier<AsyncValue<void>> {
  final InventoryRepository _repository;
  final Ref _ref;

  StockAdjustmentController(this._repository, this._ref)
    : super(const AsyncData(null));

  Future<bool> adjust({
    required String productId,
    required AdjustmentType type,
    required int quantity,
    required AdjustmentReason reason,
    String? reasonNote,
    bool isOverride = false,
    required ProductModel product,
  }) async {
    state = const AsyncLoading();
    try {
      await InventoryEntitlementGate(
        _ref.read(entitlementEvaluatorProvider),
      ).require('inventory.stock_adjustments');
      await _repository.adjustStock(
        productId: productId,
        type: type,
        quantity: quantity,
        reason: reason,
        reasonNote: reasonNote,
        isOverride: isOverride,
        product: product,
      );

      // Providers refresh karo taake UI update ho
      invalidateProductListProviders(_ref);
      _ref.invalidate(adjustmentsProvider);

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

class BulkPriceUpdateResult {
  final int updatedCount;
  final String? errorMessage;

  const BulkPriceUpdateResult.success(this.updatedCount) : errorMessage = null;
  const BulkPriceUpdateResult.failure(this.errorMessage) : updatedCount = 0;

  bool get isSuccess => errorMessage == null;
}

// Ek product ki adjustment history
// productId optional → null matlab sab products ki history
final adjustmentsProvider =
    FutureProvider.family<List<StockAdjustmentModel>, String?>((
      ref,
      productId,
    ) async {
      return ref
          .read(inventoryRepositoryProvider)
          .getAdjustments(productId: productId);
    });

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(
    entitlementEvaluator: ref.watch(entitlementEvaluatorProvider),
  );
});

// Selected category filter
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

// Products list
final allProductsProvider = FutureProvider<List<ProductModel>>((ref) async {
  await ref.watch(selectedBranchIdProvider.future);
  return ref.read(inventoryRepositoryProvider).fetchProducts();
});

final productsProvider = FutureProvider<List<ProductModel>>((ref) async {
  final categoryId = ref.watch(selectedCategoryProvider);
  if (categoryId == null) {
    return ref.watch(allProductsProvider.future);
  }

  await ref.watch(selectedBranchIdProvider.future);
  return ref
      .read(inventoryRepositoryProvider)
      .fetchProducts(categoryId: categoryId);
});

class InventoryProductsRequest {
  final String query;
  final String? categoryId;
  final ProductSortOption sortOption;
  final int limit;
  final int offset;
  final bool lowStockOnly;

  const InventoryProductsRequest({
    required this.query,
    this.categoryId,
    this.sortOption = ProductSortOption.nameAZ,
    this.limit = 50,
    this.offset = 0,
    this.lowStockOnly = false,
  });

  @override
  bool operator ==(Object other) {
    return other is InventoryProductsRequest &&
        other.query == query &&
        other.categoryId == categoryId &&
        other.sortOption == sortOption &&
        other.limit == limit &&
        other.offset == offset &&
        other.lowStockOnly == lowStockOnly;
  }

  @override
  int get hashCode =>
      Object.hash(query, categoryId, sortOption, limit, offset, lowStockOnly);
}

final inventoryProductsPageProvider =
    FutureProvider.family<List<ProductModel>, InventoryProductsRequest>((
      ref,
      request,
    ) async {
      await ref.watch(selectedBranchIdProvider.future);
      return ref
          .read(inventoryRepositoryProvider)
          .searchProducts(
            query: request.query.trim(),
            categoryId: request.categoryId,
            sortOption: request.sortOption,
            limit: request.limit,
            offset: request.offset,
            lowStockOnly: request.lowStockOnly,
          );
    });

final inventoryProductsProvider =
    FutureProvider.family<List<ProductModel>, InventoryProductsRequest>((
      ref,
      request,
    ) async {
      const pageSize = 50;
      final requestedLimit = request.limit < 1 ? 1 : request.limit;
      final products = <ProductModel>[];

      while (products.length < requestedLimit) {
        final remaining = requestedLimit - products.length;
        final currentPageSize = remaining > pageSize ? pageSize : remaining;
        final pageRequest = InventoryProductsRequest(
          query: request.query,
          categoryId: request.categoryId,
          sortOption: request.sortOption,
          limit: currentPageSize,
          offset: request.offset + products.length,
          lowStockOnly: request.lowStockOnly,
        );
        final page = await ref.watch(
          inventoryProductsPageProvider(pageRequest).future,
        );
        products.addAll(page);

        if (page.length < currentPageSize) break;
      }

      return products;
    });

class ProductSearchRequest {
  final String query;
  final String? categoryId;
  final int limit;
  final int offset;

  const ProductSearchRequest({
    required this.query,
    this.categoryId,
    this.limit = 50,
    this.offset = 0,
  });

  @override
  bool operator ==(Object other) {
    return other is ProductSearchRequest &&
        other.query == query &&
        other.categoryId == categoryId &&
        other.limit == limit &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(query, categoryId, limit, offset);
}

final productSearchProvider =
    FutureProvider.family<List<ProductModel>, ProductSearchRequest>((
      ref,
      request,
    ) async {
      await ref.watch(selectedBranchIdProvider.future);
      final query = request.query.trim();

      return ref
          .read(inventoryRepositoryProvider)
          .searchProducts(
            query: query,
            categoryId: request.categoryId,
            limit: request.limit,
            offset: request.offset,
            preferRemote: true,
          );
    });

void invalidateProductListProviders(Ref ref) {
  ref.invalidate(allProductsProvider);
  ref.invalidate(productsProvider);
  ref.invalidate(inventoryProductsPageProvider);
  ref.invalidate(inventoryProductsProvider);
  ref.invalidate(productSearchProvider);
}

// Categories list
final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  await ref.watch(selectedBranchIdProvider.future);
  return ref.read(inventoryRepositoryProvider).fetchCategories();
});

final productPriceHistoryProvider =
    FutureProvider.family<List<PriceHistoryModel>, String>((
      ref,
      productId,
    ) async {
      return ref.read(inventoryRepositoryProvider).fetchPriceHistory(productId);
    });

final activeImeiUnitsProvider = FutureProvider.family<bool, String>((
  ref,
  productId,
) async {
  return ref
      .read(inventoryRepositoryProvider)
      .productHasActiveImeiUnits(productId);
});

// Product CRUD controller
final productControllerProvider =
    StateNotifierProvider<ProductController, AsyncValue<void>>((ref) {
      return ProductController(ref.read(inventoryRepositoryProvider), ref);
    });

class ProductController extends StateNotifier<AsyncValue<void>> {
  final InventoryRepository _repository;
  final Ref _ref;

  ProductController(this._repository, this._ref) : super(const AsyncData(null));

  Future<bool> addProduct(ProductModel product) async {
    state = const AsyncLoading();
    try {
      if (product.imeiTracked) {
        await InventoryEntitlementGate(
          _ref.read(entitlementEvaluatorProvider),
        ).require('inventory.imei_tracking');
      }
      await _repository.addProduct(product);
      invalidateProductListProviders(_ref);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> updateProduct(ProductModel product) async {
    state = const AsyncLoading();
    try {
      if (product.imeiTracked) {
        await InventoryEntitlementGate(
          _ref.read(entitlementEvaluatorProvider),
        ).require('inventory.imei_tracking');
      }
      await _repository.updateProduct(product);
      invalidateProductListProviders(_ref);
      _ref.invalidate(productPriceHistoryProvider(product.id));
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> deleteProduct(String productId) async {
    state = const AsyncLoading();
    try {
      await _repository.deleteProduct(productId);
      invalidateProductListProviders(_ref);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<BulkPriceUpdateResult> bulkUpdatePrices(
    BulkPriceUpdateRequest request,
  ) async {
    state = const AsyncLoading();
    try {
      await InventoryEntitlementGate(
        _ref.read(entitlementEvaluatorProvider),
      ).require('inventory.bulk_pricing');
      final updatedCount = await _repository.bulkUpdateProductPrices(
        products: request.products,
        percentage: request.percentage,
        direction: request.direction,
      );
      invalidateProductListProviders(_ref);
      for (final productId in request.productIds) {
        _ref.invalidate(productPriceHistoryProvider(productId));
      }
      state = const AsyncData(null);
      return BulkPriceUpdateResult.success(updatedCount);
    } catch (e, st) {
      state = AsyncError(e, st);
      return BulkPriceUpdateResult.failure(e.toString());
    }
  }
}

// Category controller
final categoryControllerProvider =
    StateNotifierProvider<CategoryController, AsyncValue<void>>((ref) {
      return CategoryController(ref.read(inventoryRepositoryProvider), ref);
    });

class CategoryController extends StateNotifier<AsyncValue<void>> {
  final InventoryRepository _repository;
  final Ref _ref;

  CategoryController(this._repository, this._ref)
    : super(const AsyncData(null));

  Future<bool> addCategory(String name) async {
    state = const AsyncLoading();
    try {
      await _repository.addCategory(name);
      _ref.invalidate(categoriesProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> deleteCategory(String categoryId) async {
    state = const AsyncLoading();
    try {
      await _repository.deleteCategory(categoryId);
      _ref.invalidate(categoriesProvider);
      invalidateProductListProviders(_ref);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final searchQueryProvider = StateProvider<String>((ref) => '');

final sortOptionProvider = StateProvider<ProductSortOption>(
  (ref) => ProductSortOption.nameAZ,
);

final filteredProductsProvider = Provider<AsyncValue<List<ProductModel>>>((
  ref,
) {
  final productsAsync = ref.watch(productsProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase().trim();
  final sortOption = ref.watch(sortOptionProvider);

  return productsAsync.whenData((products) {
    // 1. Search filter
    var filtered =
        products.where((p) {
          if (query.isEmpty) return true;
          // Naam ya SKU se match karo
          final nameMatch = p.name.toLowerCase().contains(query);
          final skuMatch = p.sku?.toLowerCase().contains(query) ?? false;
          return nameMatch || skuMatch;
        }).toList();

    // 2. Sort
    switch (sortOption) {
      case ProductSortOption.nameAZ:
        filtered.sort((a, b) => a.name.compareTo(b.name));
      case ProductSortOption.nameZA:
        filtered.sort((a, b) => b.name.compareTo(a.name));
      case ProductSortOption.priceLow:
        filtered.sort((a, b) => a.salePrice.compareTo(b.salePrice));
      case ProductSortOption.priceHigh:
        filtered.sort((a, b) => b.salePrice.compareTo(a.salePrice));
      case ProductSortOption.stockLow:
        filtered.sort((a, b) => a.stock.compareTo(b.stock));
      case ProductSortOption.stockHigh:
        filtered.sort((a, b) => b.stock.compareTo(a.stock));
    }

    return filtered;
  });
});
