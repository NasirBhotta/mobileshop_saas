class CustomerModel {
  final String? id;
  final String tenantId;
  final String branchId;
  final String fullName;
  final String? phone;
  final String? email;
  final String? notes;
  final DateTime? createdAt;

  const CustomerModel({
    this.id,
    required this.tenantId,
    required this.branchId,
    required this.fullName,
    this.phone,
    this.email,
    this.notes,
    this.createdAt,
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      id: map['id'] as String?,
      tenantId: map['tenant_id'] as String,
      branchId: map['branch_id'] as String,
      fullName: map['full_name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      notes: map['notes'] as String?,
      createdAt:
          map['created_at'] != null
              ? DateTime.parse(map['created_at'] as String)
              : null,
    );
  }

  Map<String, dynamic> toInsertMap({
    required String tenantId,
    required String branchId,
  }) => {
    'tenant_id': tenantId,
    'branch_id': branchId,
    'full_name': fullName,
    'phone': phone,
    'email': email,
    'notes': notes,
  };

  // Search ke liye
  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    return fullName.toLowerCase().contains(q) ||
        (phone?.contains(q) ?? false) ||
        (email?.toLowerCase().contains(q) ?? false);
  }
}
