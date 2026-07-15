class PlatformTenant {
  final String id;
  final String shopName;
  final String businessType;
  final String status;
  final String plan;
  final int branchCount;
  final int userCount;
  final DateTime createdAt;

  const PlatformTenant({
    required this.id,
    required this.shopName,
    required this.businessType,
    required this.status,
    required this.plan,
    required this.branchCount,
    required this.userCount,
    required this.createdAt,
  });

  factory PlatformTenant.fromJson(Map<String, dynamic> json) => PlatformTenant(
    id: json['id'] as String,
    shopName: json['shop_name'] as String? ?? '',
    businessType: json['business_type'] as String? ?? '',
    status: json['status'] as String? ?? '',
    plan: json['plan'] as String? ?? '',
    branchCount: (json['branch_count'] as num?)?.toInt() ?? 0,
    userCount: (json['user_count'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

class TenantSummary {
  final int total;
  final int active;
  final int suspended;
  final int starter;
  final int business;
  final int enterprise;

  const TenantSummary({
    required this.total,
    required this.active,
    required this.suspended,
    required this.starter,
    required this.business,
    required this.enterprise,
  });

  factory TenantSummary.fromJson(Map<String, dynamic> json) => TenantSummary(
    total: (json['total_tenants'] as num?)?.toInt() ?? 0,
    active: (json['active_tenants'] as num?)?.toInt() ?? 0,
    suspended: (json['suspended_tenants'] as num?)?.toInt() ?? 0,
    starter: (json['starter_tenants'] as num?)?.toInt() ?? 0,
    business: (json['business_tenants'] as num?)?.toInt() ?? 0,
    enterprise: (json['enterprise_tenants'] as num?)?.toInt() ?? 0,
  );
}
