class ProductModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String? categoryId;
  final String? categoryName;
  final String name;
  final String? sku;
  final String? description;
  final double salePrice;
  final double costPrice;
  final bool imeiTracked;
  final bool isActive;
  final int stock;
  final int reorderThreshold; // ← product-level default (naya)
  final int branchThreshold; // ← branch-level override (inventory se)
  final int categoryThreshold; // ← category default (join se)

  const ProductModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    this.categoryId,
    this.categoryName,
    required this.name,
    this.sku,
    this.description,
    required this.salePrice,
    required this.costPrice,
    this.imeiTracked = false,
    this.isActive = true,
    this.stock = 0,
    this.reorderThreshold = 0, // 0 matlab product-level threshold set nahi
    this.branchThreshold = 0, // ← 0 matlab set nahi
    this.categoryThreshold = 0, // ← 0 matlab set nahi
  });

  // ── Yeh property decide kare gi effective threshold ──
  // Branch > Product > Category > System(5)
  int get effectiveThreshold {
    if (branchThreshold > 0) return branchThreshold;
    if (reorderThreshold > 0) return reorderThreshold;
    if (categoryThreshold > 0) return categoryThreshold;
    return 5; // system default
  }

  // ── Yeh properties dashboard aur product card use karein ge ──
  bool get isLowStock => stock > 0 && stock <= effectiveThreshold;
  bool get isOutOfStock => stock == 0;

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    final category = map['categories'] as Map<String, dynamic>?;
    final invList = map['inventory'] as List<dynamic>?;
    final firstInv =
        invList?.isNotEmpty == true
            ? invList!.first as Map<String, dynamic>
            : null;

    // Stock — inventory se
    final totalStock =
        invList?.fold<int>(
          0,
          (sum, inv) => sum + ((inv['quantity'] as num?)?.toInt() ?? 0),
        ) ??
        (map['stock'] as num?)?.toInt() ??
        0;

    return ProductModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      categoryId: map['category_id'] as String?,
      categoryName:
          category?['name'] as String? ?? map['category_name'] as String?,
      name: map['name'] as String,
      sku: map['sku'] as String?,
      description: map['description'] as String?,
      salePrice: (map['sale_price'] as num).toDouble(),
      costPrice: (map['cost_price'] as num).toDouble(),
      imeiTracked: map['imei_tracked'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      stock: totalStock,

      // Product-level threshold (products table se)
      reorderThreshold: (map['reorder_threshold'] as num?)?.toInt() ?? 0,

      // Branch-level threshold (inventory table se)
      branchThreshold:
          (firstInv?['reorder_threshold'] as num?)?.toInt() ??
          (map['branch_threshold'] as num?)?.toInt() ??
          0,

      // Category-level threshold (categories join se)
      categoryThreshold:
          (category?['default_reorder_threshold'] as num?)?.toInt() ??
          (map['category_threshold'] as num?)?.toInt() ??
          0,
    );
  }

  Map<String, dynamic> toInsertMap({
    required String tenantId,
    required String branchId,
  }) => {
    'tenant_id': tenantId,
    'branch_id': branchId,
    'category_id': categoryId,
    'name': name,
    'sku': sku?.isEmpty == true ? null : sku,
    'description': description?.isEmpty == true ? null : description,
    'sale_price': salePrice,
    'cost_price': costPrice,
    'imei_tracked': imeiTracked,
    'is_active': isActive,
    'reorder_threshold': reorderThreshold, // ← save karo
  };

  Map<String, dynamic> toCacheMap() => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'category_id': categoryId,
    'categories': categoryName != null ? {'name': categoryName} : null,
    'name': name,
    'sku': sku,
    'description': description,
    'sale_price': salePrice,
    'cost_price': costPrice,
    'imei_tracked': imeiTracked,
    'is_active': isActive,
    'stock': stock,
    'reorder_threshold': reorderThreshold,
    'branch_threshold': branchThreshold,
    'category_threshold': categoryThreshold,
  };

  Object? copyWith({required int stock}) {
    return null;
  }
}
