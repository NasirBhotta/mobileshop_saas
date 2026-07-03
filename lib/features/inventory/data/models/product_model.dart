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
  final int stock; // inventory table se aayega

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
  });

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    final category = map['categories'] as Map<String, dynamic>?;
    final inventoryList = map['inventory'] as List<dynamic>?;
    final totalStock =
        inventoryList?.fold<int>(
          0,
          (sum, inv) => sum + ((inv['quantity'] as num?)?.toInt() ?? 0),
        ) ??
        0;

    return ProductModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      categoryId: map['category_id'] as String?,
      categoryName: category?['name'] as String?,
      name: map['name'] as String,
      sku: map['sku'] as String?,
      description: map['description'] as String?,
      salePrice: (map['sale_price'] as num).toDouble(),
      costPrice: (map['cost_price'] as num).toDouble(),
      imeiTracked: map['imei_tracked'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      stock: totalStock,
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
  };
}
