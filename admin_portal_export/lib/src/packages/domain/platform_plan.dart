class PlatformPlan {
  final String id;
  final String key;
  final String name;
  final String? description;
  final double? monthlyPrice;
  final bool isActive;
  final int affectedTenantCount;
  final DateTime createdAt;

  const PlatformPlan({
    required this.id,
    required this.key,
    required this.name,
    required this.description,
    required this.monthlyPrice,
    required this.isActive,
    required this.affectedTenantCount,
    required this.createdAt,
  });

  factory PlatformPlan.fromJson(Map<String, dynamic> json) => PlatformPlan(
    id: json['id'] as String,
    key: json['key'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    monthlyPrice: (json['monthly_price'] as num?)?.toDouble(),
    isActive: json['is_active'] as bool? ?? false,
    affectedTenantCount: (json['affected_tenant_count'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

class PlanFeature {
  final String id;
  final String key;
  final String module;
  final String name;
  final String? description;
  final bool enabled;

  const PlanFeature({
    required this.id,
    required this.key,
    required this.module,
    required this.name,
    required this.description,
    required this.enabled,
  });

  factory PlanFeature.fromJson(Map<String, dynamic> json) => PlanFeature(
    id: json['feature_id'] as String,
    key: json['feature_key'] as String,
    module: json['module'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    enabled: json['enabled'] as bool? ?? false,
  );
}

class PlanLimit {
  final String id;
  final String key;
  final double value;
  final String? reason;

  const PlanLimit({
    required this.id,
    required this.key,
    required this.value,
    required this.reason,
  });

  factory PlanLimit.fromJson(Map<String, dynamic> json) => PlanLimit(
    id: json['id'] as String,
    key: json['key'] as String,
    value: (json['value'] as num).toDouble(),
    reason: json['reason'] as String?,
  );
}
