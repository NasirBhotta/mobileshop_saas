import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/platform_tenant.dart';

class TenantAdminRepository {
  final SupabaseClient _client;

  TenantAdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<TenantSummary> loadSummary() async {
    final rows = await _client.rpc('platform_tenant_summary') as List;
    return TenantSummary.fromJson(
      Map<String, dynamic>.from(rows.single as Map),
    );
  }

  Future<List<PlatformTenant>> listTenants({
    String? search,
    String? status,
    String? plan,
  }) async {
    final rows =
        await _client.rpc(
              'platform_list_tenants',
              params: {'p_search': search, 'p_status': status, 'p_plan': plan},
            )
            as List;
    return rows
        .map(
          (row) =>
              PlatformTenant.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<PlatformTenant> getTenant(String id) async {
    final rows =
        await _client.rpc('platform_get_tenant', params: {'p_tenant_id': id})
            as List;
    if (rows.isEmpty) throw StateError('Tenant not found.');
    return PlatformTenant.fromJson(
      Map<String, dynamic>.from(rows.single as Map),
    );
  }

  Future<void> setStatus({
    required String tenantId,
    required String status,
    String? reason,
  }) => _client.rpc(
    'platform_set_tenant_status',
    params: {'p_tenant_id': tenantId, 'p_status': status, 'p_reason': reason},
  );
}
