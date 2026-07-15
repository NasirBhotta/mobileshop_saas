class PlatformAddon {
  final String id, key, name, billingType;
  final String? description, featureId, featureKey, limitKey;
  final double price;
  final double? limitIncrease;
  final bool isActive;
  final int assignedTenants;
  const PlatformAddon({
    required this.id,
    required this.key,
    required this.name,
    required this.billingType,
    required this.price,
    required this.isActive,
    required this.assignedTenants,
    this.description,
    this.featureId,
    this.featureKey,
    this.limitKey,
    this.limitIncrease,
  });
  factory PlatformAddon.fromJson(Map<String, dynamic> j) => PlatformAddon(
    id: j['id'] as String,
    key: j['key'] as String,
    name: j['name'] as String,
    billingType: j['billing_type'] as String,
    price: (j['price'] as num).toDouble(),
    isActive: j['is_active'] as bool,
    assignedTenants: (j['assigned_tenants'] as num).toInt(),
    description: j['description'] as String?,
    featureId: j['feature_id'] as String?,
    featureKey: j['feature_key'] as String?,
    limitKey: j['limit_key'] as String?,
    limitIncrease: (j['limit_increase'] as num?)?.toDouble(),
  );
}

class TenantAddon {
  final String id, addonId, name, status, billingType;
  final int quantity;
  final double price;
  final DateTime startsAt;
  final DateTime? expiresAt;
  const TenantAddon({
    required this.id,
    required this.addonId,
    required this.name,
    required this.status,
    required this.billingType,
    required this.quantity,
    required this.price,
    required this.startsAt,
    this.expiresAt,
  });
  factory TenantAddon.fromJson(Map<String, dynamic> j) => TenantAddon(
    id: j['assignment_id'] as String,
    addonId: j['addon_id'] as String,
    name: j['addon_name'] as String,
    status: j['status'] as String,
    billingType: j['billing_type'] as String,
    quantity: (j['quantity'] as num).toInt(),
    price: (j['price'] as num).toDouble(),
    startsAt: DateTime.parse(j['starts_at'] as String),
    expiresAt:
        j['expires_at'] == null
            ? null
            : DateTime.parse(j['expires_at'] as String),
  );
}

class TenantUsage {
  final String key, warning;
  final double used, effective, percent, addonIncrease;
  final double? packageLimit, overrideLimit;
  const TenantUsage({
    required this.key,
    required this.warning,
    required this.used,
    required this.effective,
    required this.percent,
    required this.addonIncrease,
    this.packageLimit,
    this.overrideLimit,
  });
  factory TenantUsage.fromJson(Map<String, dynamic> j) => TenantUsage(
    key: j['limit_key'] as String,
    warning: j['warning_level'] as String,
    used: (j['used_value'] as num).toDouble(),
    effective: (j['effective_limit'] as num).toDouble(),
    percent: (j['usage_percent'] as num).toDouble(),
    addonIncrease: (j['addon_increase'] as num).toDouble(),
    packageLimit: (j['plan_limit'] as num?)?.toDouble(),
    overrideLimit: (j['override_limit'] as num?)?.toDouble(),
  );
}
