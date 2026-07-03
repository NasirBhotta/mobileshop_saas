class CategoryModel {
  final String id;
  final String tenantId;
  final String branchId;
  final String name;

  const CategoryModel({
    required this.id,
    required this.tenantId,
    required this.branchId,
    required this.name,
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      name: map['name'] as String,
    );
  }
}
