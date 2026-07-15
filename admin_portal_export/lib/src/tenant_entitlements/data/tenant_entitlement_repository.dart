import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/tenant_entitlement.dart';

class TenantEntitlementRepository {
  final SupabaseClient _client;
  TenantEntitlementRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<TenantSubscriptionInfo?> getSubscription(String tenantId) async {
    final rows =
        await _client.rpc(
              'platform_admin_get_tenant_subscription',
              params: {'p_tenant_id': tenantId},
            )
            as List;
    return rows.isEmpty
        ? null
        : TenantSubscriptionInfo.fromJson(
          Map<String, dynamic>.from(rows.single as Map),
        );
  }

  Future<List<TenantFeatureEntitlement>> getFeatures(String tenantId) async =>
      _mapList(
        await _client.rpc(
          'platform_admin_get_tenant_features',
          params: {'p_tenant_id': tenantId},
        ),
        TenantFeatureEntitlement.fromJson,
      );

  Future<List<TenantLimitEntitlement>> getLimits(String tenantId) async =>
      _mapList(
        await _client.rpc(
          'platform_admin_get_tenant_limits',
          params: {'p_tenant_id': tenantId},
        ),
        TenantLimitEntitlement.fromJson,
      );

  Future<void> changePlan({
    required String tenantId,
    required String planId,
    String? reason,
  }) => _client.rpc(
    'platform_admin_set_tenant_subscription',
    params: {'p_tenant_id': tenantId, 'p_plan_id': planId, 'p_reason': reason},
  );

  Future<void> setFeatureOverride({
    required String tenantId,
    required String featureId,
    required bool enabled,
    String? reason,
    DateTime? expiresAt,
  }) => _client.rpc(
    'platform_admin_set_tenant_feature_override',
    params: {
      'p_tenant_id': tenantId,
      'p_feature_id': featureId,
      'p_enabled': enabled,
      'p_reason': reason,
      'p_expires_at': expiresAt?.toUtc().toIso8601String(),
    },
  );

  Future<void> removeFeatureOverride({
    required String tenantId,
    required String featureId,
    String? reason,
  }) => _client.rpc(
    'platform_admin_remove_tenant_feature_override',
    params: {
      'p_tenant_id': tenantId,
      'p_feature_id': featureId,
      'p_reason': reason,
    },
  );

  Future<void> setLimitOverride({
    required String tenantId,
    required String key,
    required double value,
    String? reason,
    DateTime? expiresAt,
  }) => _client.rpc(
    'platform_admin_set_tenant_limit_override',
    params: {
      'p_tenant_id': tenantId,
      'p_key': key,
      'p_value': value,
      'p_reason': reason,
      'p_expires_at': expiresAt?.toUtc().toIso8601String(),
    },
  );

  Future<void> removeLimitOverride({
    required String tenantId,
    required String key,
    String? reason,
  }) => _client.rpc(
    'platform_admin_remove_tenant_limit_override',
    params: {'p_tenant_id': tenantId, 'p_key': key, 'p_reason': reason},
  );

  List<T> _mapList<T>(dynamic rows, T Function(Map<String, dynamic>) mapper) =>
      (rows as List)
          .map((row) => mapper(Map<String, dynamic>.from(row as Map)))
          .toList();
}
