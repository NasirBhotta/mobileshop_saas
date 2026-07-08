class CustomerModel {
  final String? id;
  final String tenantId;
  final String branchId;
  final String fullName;
  final String? phone;
  final String? email;
  final String? notes;
  final double? creditLimit;
  final double outstandingBalance;
  final DateTime? createdAt;

  const CustomerModel({
    this.id,
    required this.tenantId,
    required this.branchId,
    required this.fullName,
    this.phone,
    this.email,
    this.notes,
    this.creditLimit,
    this.outstandingBalance = 0,
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
      creditLimit: (map['credit_limit'] as num?)?.toDouble(),
      outstandingBalance: (map['outstanding_balance'] as num?)?.toDouble() ?? 0,
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
    'credit_limit': creditLimit,
    'outstanding_balance': outstandingBalance,
  };

  CustomerModel copyWith({
    String? id,
    String? tenantId,
    String? branchId,
    String? fullName,
    String? phone,
    String? email,
    String? notes,
    double? creditLimit,
    bool clearCreditLimit = false,
    double? outstandingBalance,
    DateTime? createdAt,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      branchId: branchId ?? this.branchId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      creditLimit: clearCreditLimit ? null : creditLimit ?? this.creditLimit,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'branch_id': branchId,
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'notes': notes,
      'credit_limit': creditLimit,
      'outstanding_balance': outstandingBalance,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  String toString() => toJson().toString();

  // Search ke liye
  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    return fullName.toLowerCase().contains(q) ||
        (phone?.contains(q) ?? false) ||
        (email?.toLowerCase().contains(q) ?? false);
  }
}
