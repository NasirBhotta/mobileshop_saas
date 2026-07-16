import 'package:flutter/foundation.dart';

enum EntitlementValueSource {
  tenantOverride,
  planDefault,
  compatibilityPlanFallback,
  unavailable,
}

@immutable
class TenantEntitlementContext {
  final String tenantId;
  final String? compatibilityPlanKey;

  const TenantEntitlementContext({
    required this.tenantId,
    required this.compatibilityPlanKey,
  });
}

@immutable
class EntitlementFeatureValue {
  final String key;
  final bool enabled;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? deletedAt;

  const EntitlementFeatureValue({
    required this.key,
    required this.enabled,
    this.isActive = true,
    this.startsAt,
    this.expiresAt,
    this.deletedAt,
  });

  bool isEffectiveAt(DateTime now) =>
      isActive &&
      deletedAt == null &&
      (startsAt == null || !startsAt!.isAfter(now)) &&
      (expiresAt == null || expiresAt!.isAfter(now));
}

@immutable
class EntitlementLimitValue {
  final String key;
  final num value;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? deletedAt;

  const EntitlementLimitValue({
    required this.key,
    required this.value,
    this.isActive = true,
    this.startsAt,
    this.expiresAt,
    this.deletedAt,
  });

  bool isEffectiveAt(DateTime now) =>
      isActive &&
      deletedAt == null &&
      (startsAt == null || !startsAt!.isAfter(now)) &&
      (expiresAt == null || expiresAt!.isAfter(now));
}

@immutable
class TenantEntitlementSnapshot {
  final String? subscriptionPlanKey;
  final List<EntitlementFeatureValue> planFeatures;
  final List<EntitlementFeatureValue> featureOverrides;
  final List<EntitlementLimitValue> planLimits;
  final List<EntitlementLimitValue> limitOverrides;

  const TenantEntitlementSnapshot({
    required this.subscriptionPlanKey,
    this.planFeatures = const [],
    this.featureOverrides = const [],
    this.planLimits = const [],
    this.limitOverrides = const [],
  });
}

abstract interface class EntitlementDataSource {
  String? get currentUserId;

  Future<TenantEntitlementContext?> loadTenantContext(String userId);

  Future<TenantEntitlementSnapshot> loadSnapshot(String tenantId);
}

@immutable
class FeatureEntitlementResult {
  final String key;
  final String? tenantId;
  final bool isEnabled;
  final EntitlementValueSource source;
  final bool fromCache;

  const FeatureEntitlementResult({
    required this.key,
    required this.tenantId,
    required this.isEnabled,
    required this.source,
    required this.fromCache,
  });
}

@immutable
class LimitEntitlementResult {
  final String key;
  final String? tenantId;
  final num? value;
  final EntitlementValueSource source;
  final bool fromCache;

  const LimitEntitlementResult({
    required this.key,
    required this.tenantId,
    required this.value,
    required this.source,
    required this.fromCache,
  });

  bool get isUnlimited => value == null;
}

class EntitlementEvaluator {
  final EntitlementDataSource _dataSource;
  final DateTime Function() _clock;
  final Map<String, _ResolvedEntitlements> _cache = {};
  final Map<String, TenantEntitlementContext> _contextCache = {};
  final Map<String, Future<_LoadedEntitlements?>> _inFlightLoads = {};

  EntitlementEvaluator({
    required EntitlementDataSource dataSource,
    DateTime Function()? clock,
  }) : _dataSource = dataSource,
       _clock = clock ?? DateTime.now;

  Future<bool> hasFeature(String key) async =>
      (await evaluateFeature(key)).isEnabled;

  Future<num?> getLimit(String key) async => (await evaluateLimit(key)).value;

  Future<FeatureEntitlementResult> evaluateFeature(String key) async {
    final loaded = await _load();
    if (loaded == null) {
      return FeatureEntitlementResult(
        key: key,
        tenantId: null,
        isEnabled: false,
        source: EntitlementValueSource.unavailable,
        fromCache: false,
      );
    }
    final value = loaded.entitlements.features[key];
    return FeatureEntitlementResult(
      key: key,
      tenantId: loaded.tenantId,
      isEnabled: value?.enabled ?? false,
      source: value?.source ?? EntitlementValueSource.unavailable,
      fromCache: loaded.fromCache,
    );
  }

  Future<LimitEntitlementResult> evaluateLimit(String key) async {
    final loaded = await _load();
    if (loaded == null) {
      return LimitEntitlementResult(
        key: key,
        tenantId: null,
        value: null,
        source: EntitlementValueSource.unavailable,
        fromCache: false,
      );
    }
    final value = loaded.entitlements.limits[key];
    return LimitEntitlementResult(
      key: key,
      tenantId: loaded.tenantId,
      value: _normalizeLimit(value?.value),
      source: value?.source ?? EntitlementValueSource.unavailable,
      fromCache: loaded.fromCache,
    );
  }

  Future<_LoadedEntitlements?> _load() async {
    final userId = _dataSource.currentUserId;
    if (userId == null) return null;
    final pending = _inFlightLoads[userId];
    if (pending != null) return pending;

    late final Future<_LoadedEntitlements?> load;
    load = _loadForUser(userId).whenComplete(() {
      if (identical(_inFlightLoads[userId], load)) {
        _inFlightLoads.remove(userId);
      }
    });
    _inFlightLoads[userId] = load;
    return load;
  }

  Future<_LoadedEntitlements?> _loadForUser(String userId) async {
    final context =
        _contextCache[userId] ?? await _dataSource.loadTenantContext(userId);
    if (context == null) return null;
    _contextCache[userId] = context;
    final cached = _cache[context.tenantId];
    if (cached != null) {
      return _LoadedEntitlements(context.tenantId, cached, true);
    }

    final snapshot = await _dataSource.loadSnapshot(context.tenantId);
    final resolved = _resolve(snapshot, context.compatibilityPlanKey);
    _cache[context.tenantId] = resolved;
    return _LoadedEntitlements(context.tenantId, resolved, false);
  }

  _ResolvedEntitlements _resolve(
    TenantEntitlementSnapshot snapshot,
    String? compatibilityPlanKey,
  ) {
    final now = _clock().toUtc();
    final features = <String, _ResolvedFeature>{};
    final limits = <String, _ResolvedLimit>{};

    if (snapshot.subscriptionPlanKey == null) {
      _addCompatibilityFallback(features, limits, compatibilityPlanKey);
    } else {
      for (final value in snapshot.planFeatures) {
        if (value.isEffectiveAt(now)) {
          features[value.key] = _ResolvedFeature(
            value.enabled,
            EntitlementValueSource.planDefault,
          );
        }
      }
      for (final value in snapshot.planLimits) {
        if (value.isEffectiveAt(now)) {
          limits[value.key] = _ResolvedLimit(
            value.value,
            EntitlementValueSource.planDefault,
          );
        }
      }
    }

    for (final value in snapshot.featureOverrides) {
      if (value.isEffectiveAt(now)) {
        features[value.key] = _ResolvedFeature(
          value.enabled,
          EntitlementValueSource.tenantOverride,
        );
      }
    }
    for (final value in snapshot.limitOverrides) {
      if (value.isEffectiveAt(now)) {
        limits[value.key] = _ResolvedLimit(
          value.value,
          EntitlementValueSource.tenantOverride,
        );
      }
    }
    return _ResolvedEntitlements(features, limits);
  }

  void _addCompatibilityFallback(
    Map<String, _ResolvedFeature> features,
    Map<String, _ResolvedLimit> limits,
    String? planKey,
  ) {
    final plan = planKey?.toLowerCase();
    if (!const {'starter', 'business', 'enterprise'}.contains(plan)) return;
    for (final key in _featuresAvailableOnAllCompatibilityPlans) {
      features[key] = const _ResolvedFeature(
        true,
        EntitlementValueSource.compatibilityPlanFallback,
      );
    }
    features['reports.export'] = const _ResolvedFeature(
      true,
      EntitlementValueSource.compatibilityPlanFallback,
    );
    features['reports.scheduling'] = _ResolvedFeature(
      plan == 'business' || plan == 'enterprise',
      EntitlementValueSource.compatibilityPlanFallback,
    );
    limits['expenses.history_days'] = _ResolvedLimit(switch (plan) {
      'starter' => 30,
      'business' => 365,
      _ => -1,
    }, EntitlementValueSource.compatibilityPlanFallback);
  }

  void invalidateTenant(String tenantId) => _cache.remove(tenantId);

  void subscriptionChanged(String tenantId) => invalidateTenant(tenantId);

  void overrideChanged(String tenantId) => invalidateTenant(tenantId);

  void planChanged() => invalidateAll();

  void invalidateAll() {
    _cache.clear();
    _contextCache.clear();
    _inFlightLoads.clear();
  }

  static num? _normalizeLimit(num? value) =>
      value != null && value < 0 ? null : value;
}

class EntitlementDeniedException implements Exception {
  final String featureKey;
  const EntitlementDeniedException(this.featureKey);
  @override
  String toString() =>
      'This feature is not included in the current package: $featureKey';
}

const _featuresAvailableOnAllCompatibilityPlans = {
  'dashboard.access',
  'branches.access',
  'users.access',
  'inventory.access',
  'pos.access',
  'customers.access',
  'repairs.access',
  'suppliers.access',
  'purchases.access',
  'expenses.access',
  'accounts.access',
  'reports.access',
  'settings.access',
  'receipts.access',
  'purchases.procurement',
  'inventory.csv_import',
  'inventory.bulk_pricing',
  'expenses.history',
};

class _ResolvedFeature {
  final bool enabled;
  final EntitlementValueSource source;

  const _ResolvedFeature(this.enabled, this.source);
}

class _ResolvedLimit {
  final num value;
  final EntitlementValueSource source;

  const _ResolvedLimit(this.value, this.source);
}

class _ResolvedEntitlements {
  final Map<String, _ResolvedFeature> features;
  final Map<String, _ResolvedLimit> limits;

  const _ResolvedEntitlements(this.features, this.limits);
}

class _LoadedEntitlements {
  final String tenantId;
  final _ResolvedEntitlements entitlements;
  final bool fromCache;

  const _LoadedEntitlements(this.tenantId, this.entitlements, this.fromCache);
}
