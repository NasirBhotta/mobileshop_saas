import 'package:mobileshop_saas/features/inventory/data/models/category_model.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  Future<Map<String, dynamic>> _currentProfile() async {
    final profile =
        await _client
            .from('users')
            .select('tenant_id, branch_id')
            .eq('id', _currentUser.id)
            .maybeSingle();

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
    return (data as List).map((e) => ProductModel.fromMap(e)).toList();
  }

  Future<ProductModel> addProduct(ProductModel product) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final data =
        await _client
            .from('products')
            .insert(product.toInsertMap(tenantId: tenantId, branchId: branchId))
            .select('id')
            .single();

    final productId = data['id'] as String;
    await setStock(
      productId: productId,
      branchId: branchId,
      quantity: product.stock,
    );

    return fetchProduct(productId);
  }

  Future<ProductModel> updateProduct(ProductModel product) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
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

    return fetchProduct(product.id);
  }

  Future<ProductModel> fetchProduct(String productId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final data =
        await _client
            .from('products')
            .select('*, categories(name), inventory!inner(quantity, branch_id)')
            .eq('tenant_id', tenantId)
            .eq('branch_id', branchId)
            .eq('inventory.branch_id', branchId)
            .eq('id', productId)
            .single();

    return ProductModel.fromMap(data);
  }

  Future<void> deleteProduct(String productId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    await _client
        .from('products')
        .update({'is_active': false})
        .eq('id', productId)
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId);
  }

  // ── Categories ──
  Future<List<CategoryModel>> fetchCategories() async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    final data = await _client
        .from('categories')
        .select()
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId)
        .order('name');

    return (data as List).map((e) => CategoryModel.fromMap(e)).toList();
  }

  Future<CategoryModel> addCategory(String name) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
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

    return CategoryModel.fromMap(data);
  }

  Future<void> deleteCategory(String categoryId) async {
    final tenantId = await _currentTenantId();
    final branchId = await _currentBranchId(tenantId);
    await _client
        .from('categories')
        .delete()
        .eq('id', categoryId)
        .eq('tenant_id', tenantId)
        .eq('branch_id', branchId);
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
}
