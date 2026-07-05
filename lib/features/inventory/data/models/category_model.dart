class CategoryModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String name;
  final int defaultReorderThreshold; // ← naya

  const CategoryModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.name,
    this.defaultReorderThreshold = 5, // ← default 5
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      name: map['name'] as String,
      // Agar DB mein null hai toh 5 use karo
      defaultReorderThreshold:
          (map['default_reorder_threshold'] as num?)?.toInt() ?? 5,
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'name': name,
    'default_reorder_threshold': defaultReorderThreshold,
  };
}
