import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/inventory/data/models/category_model.dart';
import '../../features/inventory/data/models/product_model.dart';
import '../../features/onboarding/data/models/shop_setup_model.dart';

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

  static Future<void> saveProfile(
    String userId,
    Map<String, dynamic> profile,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey(userId), jsonEncode(profile));
    final branchId = profile['branch_id'] as String?;
    if (branchId != null) {
      await prefs.setString(_selectedBranchKey(userId), branchId);
    }
  }

  static Future<Map<String, dynamic>?> loadProfile(String userId) async {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tenantKey(tenantId), jsonEncode(tenant));
  }

  static Future<Map<String, dynamic>?> loadTenant(String tenantId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tenantKey(tenantId));
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> saveBranches(
    String tenantId,
    List<BranchInputModel> branches,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _branchesKey(tenantId),
      jsonEncode(branches.map((branch) => branch.toCacheMap()).toList()),
    );
  }

  static Future<List<BranchInputModel>> loadBranches(String tenantId) async {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _productsKey(branchId),
      jsonEncode(products.map((product) => product.toCacheMap()).toList()),
    );
  }

  static Future<List<ProductModel>> loadProducts(String branchId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_productsKey(branchId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((row) => ProductModel.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<void> upsertCachedProduct(ProductModel product) async {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _categoriesKey(branchId),
      jsonEncode(categories.map((category) => category.toCacheMap()).toList()),
    );
  }

  static Future<List<CategoryModel>> loadCategories(String branchId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_categoriesKey(branchId));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((row) => CategoryModel.fromMap(Map<String, dynamic>.from(row)))
        .toList();
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
}
