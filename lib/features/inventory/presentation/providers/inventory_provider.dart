import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/models/category_model.dart';
import '../../data/models/product_model.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../../onboarding/data/repositories/setup_flow_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository();
});

// Selected category filter
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

// Products list
final allProductsProvider = FutureProvider<List<ProductModel>>((ref) async {
  await ref.watch(setupFlowStatusProvider.future);
  return ref.read(inventoryRepositoryProvider).fetchProducts();
});

final productsProvider = FutureProvider<List<ProductModel>>((ref) async {
  final categoryId = ref.watch(selectedCategoryProvider);
  if (categoryId == null) {
    return ref.watch(allProductsProvider.future);
  }

  await ref.watch(setupFlowStatusProvider.future);
  return ref
      .read(inventoryRepositoryProvider)
      .fetchProducts(categoryId: categoryId);
});

// Categories list
final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  await ref.watch(setupFlowStatusProvider.future);
  return ref.read(inventoryRepositoryProvider).fetchCategories();
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
      await _repository.addProduct(product);
      _ref.invalidate(allProductsProvider);
      _ref.invalidate(productsProvider); // list refresh
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
      await _repository.updateProduct(product);
      _ref.invalidate(allProductsProvider);
      _ref.invalidate(productsProvider);
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
      _ref.invalidate(allProductsProvider);
      _ref.invalidate(productsProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
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
      _ref.invalidate(allProductsProvider);
      _ref.invalidate(productsProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
