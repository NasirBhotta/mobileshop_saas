class TenantSubscriptionInfo {
  final String id;
  final String planId;
  final String planKey;
  final String planName;
  final String status;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final String? reason;

  const TenantSubscriptionInfo({
    required this.id,
    required this.planId,
    required this.planKey,
    required this.planName,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.reason,
  });

  factory TenantSubscriptionInfo.fromJson(Map<String, dynamic> json) =>
      TenantSubscriptionInfo(
        id: json['subscription_id'] as String,
        planId: json['plan_id'] as String,
        planKey: json['plan_key'] as String,
        planName: json['plan_name'] as String,
        status: json['subscription_status'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        expiresAt: _date(json['expires_at']),
        reason: json['reason'] as String?,
      );
}

class TenantFeatureEntitlement {
  final String featureId;
  final String key;
  final String module;
  final String name;
  final bool planEnabled;
  final bool? overrideEnabled;
  final String? overrideReason;
  final DateTime? overrideStartsAt;
  final DateTime? overrideExpiresAt;
  final bool overrideIsEffective;
  final bool effectiveEnabled;

  const TenantFeatureEntitlement({
    required this.featureId,
    required this.key,
    required this.module,
    required this.name,
    required this.planEnabled,
    required this.overrideEnabled,
    required this.overrideReason,
    required this.overrideStartsAt,
    required this.overrideExpiresAt,
    required this.overrideIsEffective,
    required this.effectiveEnabled,
  });

  bool get hasOverride => overrideEnabled != null;

  factory TenantFeatureEntitlement.fromJson(Map<String, dynamic> json) =>
      TenantFeatureEntitlement(
        featureId: json['feature_id'] as String,
        key: json['feature_key'] as String,
        module: json['module'] as String,
        name: json['feature_name'] as String,
        planEnabled: json['plan_enabled'] as bool? ?? false,
        overrideEnabled: json['override_enabled'] as bool?,
        overrideReason: json['override_reason'] as String?,
        overrideStartsAt: _date(json['override_starts_at']),
        overrideExpiresAt: _date(json['override_expires_at']),
        overrideIsEffective: json['override_is_effective'] as bool? ?? false,
        effectiveEnabled: json['effective_enabled'] as bool? ?? false,
      );
}

class TenantLimitEntitlement {
  final String key;
  final double? planValue;
  final double? overrideValue;
  final String? overrideReason;
  final DateTime? overrideStartsAt;
  final DateTime? overrideExpiresAt;
  final bool overrideIsEffective;
  final double? effectiveValue;

  const TenantLimitEntitlement({
    required this.key,
    required this.planValue,
    required this.overrideValue,
    required this.overrideReason,
    required this.overrideStartsAt,
    required this.overrideExpiresAt,
    required this.overrideIsEffective,
    required this.effectiveValue,
  });

  bool get hasOverride => overrideValue != null;

  factory TenantLimitEntitlement.fromJson(Map<String, dynamic> json) =>
      TenantLimitEntitlement(
        key: json['limit_key'] as String,
        planValue: (json['plan_value'] as num?)?.toDouble(),
        overrideValue: (json['override_value'] as num?)?.toDouble(),
        overrideReason: json['override_reason'] as String?,
        overrideStartsAt: _date(json['override_starts_at']),
        overrideExpiresAt: _date(json['override_expires_at']),
        overrideIsEffective: json['override_is_effective'] as bool? ?? false,
        effectiveValue: (json['effective_value'] as num?)?.toDouble(),
      );
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
