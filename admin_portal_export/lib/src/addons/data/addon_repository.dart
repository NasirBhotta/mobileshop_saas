import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/platform_addon.dart';

class AddonRepository {
  final SupabaseClient _client;
  AddonRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  Future<List<Map<String, dynamic>>> _rows(
    String name, [
    Map<String, dynamic>? params,
  ]) async =>
      (await _client.rpc(name, params: params) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<List<PlatformAddon>> list() => _rows(
    'platform_list_addons',
  ).then((v) => v.map(PlatformAddon.fromJson).toList());
  Future<void> save({
    String? id,
    required String key,
    required String name,
    required double price,
    required String billingType,
    String? description,
    String? featureId,
    String? limitKey,
    double? limitIncrease,
    bool active = true,
  }) => _client.rpc(
    'platform_save_addon',
    params: {
      'p_id': id,
      'p_key': key,
      'p_name': name,
      'p_description': description,
      'p_price': price,
      'p_billing_type': billingType,
      'p_feature_id': featureId,
      'p_limit_key': limitKey,
      'p_limit_increase': limitIncrease,
      'p_is_active': active,
    },
  );
  Future<void> deactivate(String id) => _client.rpc(
    'platform_deactivate_addon',
    params: {'p_addon_id': id, 'p_reason': 'Deactivated in admin portal'},
  );
  Future<List<TenantAddon>> tenantAddons(String id) => _rows(
    'platform_list_tenant_addons',
    {'p_tenant_id': id},
  ).then((v) => v.map(TenantAddon.fromJson).toList());
  Future<List<TenantUsage>> usage(String id) => _rows(
    'platform_get_tenant_usage',
    {'p_tenant_id': id},
  ).then((v) => v.map(TenantUsage.fromJson).toList());
  Future<void> assign({
    required String tenantId,
    required String addonId,
    required int quantity,
    required DateTime startsAt,
    DateTime? expiresAt,
    required String status,
  }) => _client.rpc(
    'platform_assign_tenant_addon',
    params: {
      'p_tenant_id': tenantId,
      'p_addon_id': addonId,
      'p_quantity': quantity,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_expires_at': expiresAt?.toUtc().toIso8601String(),
      'p_status': status,
      'p_reason': 'Configured in admin portal',
    },
  );
  Future<void> remove(String id) => _client.rpc(
    'platform_remove_tenant_addon',
    params: {'p_assignment_id': id, 'p_reason': 'Removed in admin portal'},
  );
}
