import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/network.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum TenantAccessState {
  active,
  activationRequired,
  suspended,
  cancelled,
  trialExpired,
  graceExpired,
  subscriptionExpired;

  bool get isBlocked => this != TenantAccessState.active;
}

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
        .select('id, status, plan, setup_complete')
        .eq('id', tenantId)
        .maybeSingle()
        .timeout(Network.networkTimeout);
    if (tenant != null) await OfflineStore.saveTenant(tenantId, tenant);
    final subscription = await client
        .from('tenant_subscriptions')
        .select(
          'tenant_id, status, trial_ends_at, grace_ends_at, expires_at, is_active, deleted_at',
        )
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .isFilter('deleted_at', null)
        .maybeSingle()
        .timeout(Network.networkTimeout);
    await _saveSubscription(tenantId, subscription);
    final result = resolveTenantAccessState(
      tenant?['status'],
      subscription: subscription,
      requireSubscription: tenant?['setup_complete'] == true,
    );
    _scheduleDeadlineRefresh(ref, subscription);
    return result;
  } catch (_) {
    final cached = await OfflineStore.loadTenant(tenantId);
    final subscription = await _loadSubscription(tenantId);
    final result = resolveTenantAccessState(
      cached?['status'],
      subscription: subscription,
      requireSubscription: cached?['setup_complete'] == true,
    );
    _scheduleDeadlineRefresh(ref, subscription);
    return result;
  }
});

final tenantAccessRealtimeProvider = Provider<void>((ref) {
  final client = Supabase.instance.client;
  final refresh = ref.read(tenantAccessRefreshProvider);
  final tenantChannel = client.channel('tenant-status-runtime-access');
  final subscriptionChannel = client.channel(
    'tenant-subscription-runtime-access',
  );
  void handleChange(PostgresChangePayload _) {
    ref.invalidate(tenantAccessProvider);
    refresh.refresh();
  }

  void handleSubscriptionStatus(
    String source,
    RealtimeSubscribeStatus status,
    Object? error,
  ) {
    debugPrint(
      'Tenant access realtime [$source]: $status${error == null ? '' : ' ($error)'}',
    );
    if (status == RealtimeSubscribeStatus.subscribed) {
      ref.invalidate(tenantAccessProvider);
      refresh.refresh();
    }
  }

  tenantChannel
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'tenants',
        callback: handleChange,
      )
      .subscribe(
        (status, error) => handleSubscriptionStatus('tenant', status, error),
      );

  subscriptionChannel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tenant_subscriptions',
        callback: handleChange,
      )
      .subscribe(
        (status, error) =>
            handleSubscriptionStatus('subscription', status, error),
      );

  ref.onDispose(() {
    client.removeChannel(tenantChannel);
    client.removeChannel(subscriptionChannel);
  });
});

TenantAccessState resolveTenantAccessState(
  Object? tenantStatus, {
  Map<String, dynamic>? subscription,
  DateTime? now,
  bool requireSubscription = false,
}) {
  if (tenantStatus?.toString().toLowerCase() == 'suspended') {
    return TenantAccessState.suspended;
  }
  if (subscription == null) {
    return requireSubscription
        ? TenantAccessState.activationRequired
        : TenantAccessState.active;
  }

  final current = (now ?? DateTime.now()).toUtc();
  final status = subscription['status']?.toString().toLowerCase();
  final trialEndsAt = _date(subscription['trial_ends_at']);
  final graceEndsAt = _date(subscription['grace_ends_at']);
  final expiresAt = _date(subscription['expires_at']);

  if (status == 'suspended') return TenantAccessState.suspended;
  if (status == 'pending_activation') {
    return TenantAccessState.activationRequired;
  }
  if (status == 'cancelled') return TenantAccessState.cancelled;
  if (status == 'trial_expired') return TenantAccessState.trialExpired;
  if (status == 'trialing' &&
      trialEndsAt != null &&
      !trialEndsAt.isAfter(current)) {
    return TenantAccessState.trialExpired;
  }
  if (status == 'grace_period' &&
      graceEndsAt != null &&
      !graceEndsAt.isAfter(current)) {
    return TenantAccessState.graceExpired;
  }
  if (expiresAt != null && !expiresAt.isAfter(current)) {
    return TenantAccessState.subscriptionExpired;
  }
  return TenantAccessState.active;
}

void _scheduleDeadlineRefresh(Ref ref, Map<String, dynamic>? subscription) {
  if (subscription == null) return;
  final status = subscription['status']?.toString().toLowerCase();
  final deadline = switch (status) {
    'trialing' => _date(subscription['trial_ends_at']),
    'grace_period' => _date(subscription['grace_ends_at']),
    _ => _date(subscription['expires_at']),
  };
  if (deadline == null) return;
  final delay = deadline.difference(DateTime.now().toUtc());
  if (delay <= Duration.zero) return;
  final timer = Timer(delay, () {
    ref.invalidate(tenantAccessProvider);
    ref.read(tenantAccessRefreshProvider).refresh();
  });
  ref.onDispose(timer.cancel);
}

Future<void> _saveSubscription(
  String tenantId,
  Map<String, dynamic>? subscription,
) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'offline.tenant_subscription.$tenantId';
  if (subscription == null) {
    await prefs.remove(key);
  } else {
    await prefs.setString(key, jsonEncode(subscription));
  }
}

Future<Map<String, dynamic>?> _loadSubscription(String tenantId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('offline.tenant_subscription.$tenantId');
  if (raw == null) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return null;
  }
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}
