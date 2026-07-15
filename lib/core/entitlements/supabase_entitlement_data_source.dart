import 'dart:convert';

import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/network.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'entitlement_evaluator.dart';

class SupabaseEntitlementDataSource implements EntitlementDataSource {
  final SupabaseClient _client;

  SupabaseEntitlementDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<TenantEntitlementContext?> loadTenantContext(String userId) async {
    try {
      final profile = await _client
          .from('users')
          .select('tenant_id')
          .eq('id', userId)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      final tenantId = profile?['tenant_id'] as String?;
      if (tenantId == null) return null;
      final tenant = await _client
          .from('tenants')
          .select('id, plan')
          .eq('id', tenantId)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      if (tenant != null) await OfflineStore.saveTenant(tenantId, tenant);
      return TenantEntitlementContext(
        tenantId: tenantId,
        compatibilityPlanKey: tenant?['plan'] as String?,
      );
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      final profile = await OfflineStore.loadProfile(userId);
      final tenantId = profile?['tenant_id'] as String?;
      if (tenantId == null) return null;
      final tenant = await OfflineStore.loadTenant(tenantId);
      return TenantEntitlementContext(
        tenantId: tenantId,
        compatibilityPlanKey: tenant?['plan'] as String?,
      );
    }
  }

  @override
  Future<TenantEntitlementSnapshot> loadSnapshot(String tenantId) async {
    try {
      final subscription = await _client
          .from('tenant_subscriptions')
          .select('plan_id, plans!inner(key)')
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .isFilter('deleted_at', null)
          .maybeSingle()
          .timeout(Network.networkTimeout);
      if (subscription == null) {
        const snapshot = TenantEntitlementSnapshot(subscriptionPlanKey: null);
        await _saveSnapshot(tenantId, snapshot);
        return snapshot;
      }

      final planId = subscription['plan_id'] as String;
      final plan = subscription['plans'] as Map<String, dynamic>;
      final results = await Future.wait([
        _client
            .from('plan_features')
            .select(
              'enabled, is_active, starts_at, expires_at, deleted_at, features!inner(key)',
            )
            .eq('plan_id', planId),
        _client
            .from('plan_limits')
            .select('key, value, is_active, starts_at, expires_at, deleted_at')
            .eq('plan_id', planId),
        _client
            .from('tenant_feature_overrides')
            .select(
              'enabled, is_active, starts_at, expires_at, deleted_at, features!inner(key)',
            )
            .eq('tenant_id', tenantId),
        _client
            .from('tenant_limit_overrides')
            .select('key, value, is_active, starts_at, expires_at, deleted_at')
            .eq('tenant_id', tenantId),
      ]).timeout(Network.networkTimeout);

      final snapshot = TenantEntitlementSnapshot(
        subscriptionPlanKey: plan['key'] as String,
        planFeatures: _featureValues(results[0]),
        planLimits: _limitValues(results[1]),
        featureOverrides: _featureValues(results[2]),
        limitOverrides: _limitValues(results[3]),
      );
      await _saveSnapshot(tenantId, snapshot);
      return snapshot;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      return await _loadSavedSnapshot(tenantId) ??
          const TenantEntitlementSnapshot(subscriptionPlanKey: null);
    }
  }

  Future<void> _saveSnapshot(
    String tenantId,
    TenantEntitlementSnapshot snapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'offline.entitlements.$tenantId',
      jsonEncode({
        'subscription_plan_key': snapshot.subscriptionPlanKey,
        'plan_features': snapshot.planFeatures.map(_featureMap).toList(),
        'feature_overrides':
            snapshot.featureOverrides.map(_featureMap).toList(),
        'plan_limits': snapshot.planLimits.map(_limitMap).toList(),
        'limit_overrides': snapshot.limitOverrides.map(_limitMap).toList(),
      }),
    );
  }

  Future<TenantEntitlementSnapshot?> _loadSavedSnapshot(String tenantId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('offline.entitlements.$tenantId');
    if (raw == null) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return TenantEntitlementSnapshot(
        subscriptionPlanKey: map['subscription_plan_key'] as String?,
        planFeatures: _savedFeatures(map['plan_features']),
        featureOverrides: _savedFeatures(map['feature_overrides']),
        planLimits: _savedLimits(map['plan_limits']),
        limitOverrides: _savedLimits(map['limit_overrides']),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _featureMap(EntitlementFeatureValue value) => {
    'key': value.key,
    'enabled': value.enabled,
    'is_active': value.isActive,
    'starts_at': value.startsAt?.toIso8601String(),
    'expires_at': value.expiresAt?.toIso8601String(),
    'deleted_at': value.deletedAt?.toIso8601String(),
  };

  Map<String, dynamic> _limitMap(EntitlementLimitValue value) => {
    'key': value.key,
    'value': value.value,
    'is_active': value.isActive,
    'starts_at': value.startsAt?.toIso8601String(),
    'expires_at': value.expiresAt?.toIso8601String(),
    'deleted_at': value.deletedAt?.toIso8601String(),
  };

  List<EntitlementFeatureValue> _savedFeatures(dynamic values) => [
    for (final raw in values as List? ?? const [])
      EntitlementFeatureValue(
        key: raw['key'] as String,
        enabled: raw['enabled'] as bool? ?? false,
        isActive: raw['is_active'] as bool? ?? false,
        startsAt: _date(raw['starts_at']),
        expiresAt: _date(raw['expires_at']),
        deletedAt: _date(raw['deleted_at']),
      ),
  ];

  List<EntitlementLimitValue> _savedLimits(dynamic values) => [
    for (final raw in values as List? ?? const [])
      EntitlementLimitValue(
        key: raw['key'] as String,
        value: raw['value'] as num,
        isActive: raw['is_active'] as bool? ?? false,
        startsAt: _date(raw['starts_at']),
        expiresAt: _date(raw['expires_at']),
        deletedAt: _date(raw['deleted_at']),
      ),
  ];

  List<EntitlementFeatureValue> _featureValues(List<dynamic> rows) => [
    for (final raw in rows)
      EntitlementFeatureValue(
        key: (raw['features'] as Map<String, dynamic>)['key'] as String,
        enabled: raw['enabled'] as bool? ?? false,
        isActive: raw['is_active'] as bool? ?? false,
        startsAt: _date(raw['starts_at']),
        expiresAt: _date(raw['expires_at']),
        deletedAt: _date(raw['deleted_at']),
      ),
  ];

  List<EntitlementLimitValue> _limitValues(List<dynamic> rows) => [
    for (final raw in rows)
      EntitlementLimitValue(
        key: raw['key'] as String,
        value: raw['value'] as num,
        isActive: raw['is_active'] as bool? ?? false,
        startsAt: _date(raw['starts_at']),
        expiresAt: _date(raw['expires_at']),
        deletedAt: _date(raw['deleted_at']),
      ),
  ];

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
}
