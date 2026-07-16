import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/network.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum TenantAccessState { active, suspended }

class TenantAccessRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final tenantAccessRefreshProvider = Provider<TenantAccessRefresh>((ref) {
  final notifier = TenantAccessRefresh();
  ref.onDispose(notifier.dispose);
  return notifier;
});

final tenantAccessProvider = FutureProvider<TenantAccessState>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return TenantAccessState.active;

  Map<String, dynamic>? profile;
  try {
    profile = await client
        .from('users')
        .select('tenant_id')
        .eq('id', user.id)
        .maybeSingle()
        .timeout(Network.networkTimeout);
  } catch (_) {
    profile = await OfflineStore.loadProfile(user.id);
  }
  final tenantId = profile?['tenant_id'] as String?;
  if (tenantId == null) return TenantAccessState.active;

  try {
    final tenant = await client
        .from('tenants')
        .select('id, status, plan')
        .eq('id', tenantId)
        .maybeSingle()
        .timeout(Network.networkTimeout);
    if (tenant != null) await OfflineStore.saveTenant(tenantId, tenant);
    return resolveTenantAccessState(tenant?['status']);
  } catch (_) {
    final cached = await OfflineStore.loadTenant(tenantId);
    return resolveTenantAccessState(cached?['status']);
  }
});

final tenantAccessRealtimeProvider = Provider<void>((ref) {
  final client = Supabase.instance.client;
  final refresh = ref.read(tenantAccessRefreshProvider);
  final channel = client.channel('tenant-runtime-access');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'tenants',
        callback: (_) {
          ref.invalidate(tenantAccessProvider);
          refresh.refresh();
        },
      )
      .subscribe();
  ref.onDispose(() => client.removeChannel(channel));
});

TenantAccessState resolveTenantAccessState(Object? value) {
  return value?.toString().toLowerCase() == 'suspended'
      ? TenantAccessState.suspended
      : TenantAccessState.active;
}
