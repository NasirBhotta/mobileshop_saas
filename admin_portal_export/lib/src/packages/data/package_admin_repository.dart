import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/platform_plan.dart';

class PackageAdminRepository {
  final SupabaseClient _client;
  PackageAdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<PlatformPlan>> listPlans() async => _mapList(
    await _client.rpc('platform_admin_list_plans'),
    PlatformPlan.fromJson,
  );

  Future<PlatformPlan> getPlan(String id) async {
    final rows =
        await _client.rpc('platform_admin_get_plan', params: {'p_plan_id': id})
            as List;
    if (rows.isEmpty) throw StateError('Plan not found.');
    return PlatformPlan.fromJson(Map<String, dynamic>.from(rows.single as Map));
  }

  Future<List<PlanFeature>> listFeatures(String planId) async => _mapList(
    await _client.rpc(
      'platform_admin_list_plan_features',
      params: {'p_plan_id': planId},
    ),
    PlanFeature.fromJson,
  );

  Future<List<PlanLimit>> listLimits(String planId) async => _mapList(
    await _client.rpc(
      'platform_admin_list_plan_limits',
      params: {'p_plan_id': planId},
    ),
    PlanLimit.fromJson,
  );

  Future<String> savePlan({
    String? id,
    required String key,
    required String name,
    String? description,
    double? monthlyPrice,
  }) async {
    final result = await _client.rpc(
      'platform_admin_upsert_plan',
      params: {
        'p_plan_id': id,
        'p_key': key,
        'p_name': name,
        'p_description': description,
        'p_monthly_price': monthlyPrice,
      },
    );
    return result as String;
  }

  Future<void> setPlanActive(String id, bool active) => _client.rpc(
    'platform_admin_set_plan_active',
    params: {'p_plan_id': id, 'p_is_active': active},
  );

  Future<void> setFeature(String planId, String featureId, bool enabled) =>
      _client.rpc(
        'platform_admin_set_plan_feature',
        params: {
          'p_plan_id': planId,
          'p_feature_id': featureId,
          'p_enabled': enabled,
          'p_reason': 'Platform admin portal',
        },
      );

  Future<void> setLimit(String planId, String key, double value) => _client.rpc(
    'platform_admin_set_plan_limit',
    params: {
      'p_plan_id': planId,
      'p_key': key,
      'p_value': value,
      'p_reason': 'Platform admin portal',
    },
  );

  List<T> _mapList<T>(dynamic rows, T Function(Map<String, dynamic>) mapper) =>
      (rows as List)
          .map((row) => mapper(Map<String, dynamic>.from(row as Map)))
          .toList();
}
