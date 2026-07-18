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
  subscriptionExpired,
  offlineVerificationRequired,
  accessConfigurationError;

  bool get isBlocked => this != TenantAccessState.active;
}

const _offlineAccessDuration = Duration(hours: 48);
const _allowedClockRollback = Duration(minutes: 5);

class _TenantAccessLease {
  final TenantAccessState state;

  /// Server ka trusted UTC time jab access verify hua.
  final DateTime serverVerifiedAt;

  /// Verification ke waqt device ka UTC time.
  final DateTime deviceTimeAtVerification;

  /// Device par ab tak dekha gaya maximum time.
  final DateTime lastObservedDeviceTime;

  /// Server time ke according offline access deadline.
  final DateTime offlineAccessUntil;

  const _TenantAccessLease({
    required this.state,
    required this.serverVerifiedAt,
    required this.deviceTimeAtVerification,
    required this.lastObservedDeviceTime,
    required this.offlineAccessUntil,
  });

  _TenantAccessLease copyWith({
    TenantAccessState? state,
    DateTime? serverVerifiedAt,
    DateTime? deviceTimeAtVerification,
    DateTime? lastObservedDeviceTime,
    DateTime? offlineAccessUntil,
  }) {
    return _TenantAccessLease(
      state: state ?? this.state,
      serverVerifiedAt: serverVerifiedAt ?? this.serverVerifiedAt,
      deviceTimeAtVerification:
          deviceTimeAtVerification ?? this.deviceTimeAtVerification,
      lastObservedDeviceTime:
          lastObservedDeviceTime ?? this.lastObservedDeviceTime,
      offlineAccessUntil: offlineAccessUntil ?? this.offlineAccessUntil,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'state': state.name,
      'server_verified_at': serverVerifiedAt.toIso8601String(),
      'device_time_at_verification': deviceTimeAtVerification.toIso8601String(),
      'last_observed_device_time': lastObservedDeviceTime.toIso8601String(),
      'offline_access_until': offlineAccessUntil.toIso8601String(),
    };
  }

  factory _TenantAccessLease.fromJson(Map<String, dynamic> json) {
    final state = _tenantAccessStateFromName(json['state']?.toString());

    if (state == null) {
      throw const FormatException('Unknown tenant access state');
    }

    return _TenantAccessLease(
      state: state,
      serverVerifiedAt:
          DateTime.parse(json['server_verified_at'] as String).toUtc(),
      deviceTimeAtVerification:
          DateTime.parse(json['device_time_at_verification'] as String).toUtc(),
      lastObservedDeviceTime:
          DateTime.parse(json['last_observed_device_time'] as String).toUtc(),
      offlineAccessUntil:
          DateTime.parse(json['offline_access_until'] as String).toUtc(),
    );
  }
}

TenantAccessState? _tenantAccessStateFromName(String? name) {
  for (final state in TenantAccessState.values) {
    if (state.name == name) return state;
  }

  return null;
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

  final Map<String, dynamic>? profile;
  try {
    profile = await client
        .from('users')
        .select('tenant_id')
        .eq('id', user.id)
        .maybeSingle()
        .timeout(Network.networkTimeout);
  } catch (error) {
    debugPrint('Tenant access profile lookup failed: $error');
    final cachedProfile = await _loadCachedProfile(user.id);
    final cachedTenantId = cachedProfile?['tenant_id'] as String?;
    if (cachedTenantId == null) {
      return TenantAccessState.offlineVerificationRequired;
    }
    return _resolveOfflineAccess(cachedTenantId);
  }

  final tenantId = profile?['tenant_id'] as String?;
  if (tenantId == null) return TenantAccessState.active;

  Map<String, dynamic>? tenant;
  Map<String, dynamic>? subscription;
  try {
    tenant = await client
        .from('tenants')
        .select('id, status, plan, setup_complete')
        .eq('id', tenantId)
        .maybeSingle()
        .timeout(Network.networkTimeout);
    subscription = await client
        .from('tenant_subscriptions')
        .select(
          'tenant_id, status, trial_ends_at, grace_ends_at, expires_at, is_active, deleted_at',
        )
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .isFilter('deleted_at', null)
        .maybeSingle()
        .timeout(Network.networkTimeout);
  } catch (error) {
    debugPrint('Tenant access lookup failed: $error');
    return _resolveOfflineAccessAndSchedule(ref, tenantId);
  }

  // A successful online lookup with no tenant is not an offline condition.
  // Never issue an active lease for an invalid or inaccessible tenant row.
  if (tenant == null) return TenantAccessState.activationRequired;

  final DateTime serverNow;
  try {
    serverNow = await _loadServerUtcNow(client);
  } catch (error) {
    debugPrint('Trusted server time lookup failed: $error');
    return _resolveOfflineAccessAndSchedule(ref, tenantId);
  }

  final result = resolveTenantAccessState(
    tenant['status'],
    subscription: subscription,
    requireSubscription: tenant['setup_complete'] == true,
    now: serverNow,
  );

  final deviceNow = DateTime.now().toUtc();
  final lease = _TenantAccessLease(
    state: result,
    serverVerifiedAt: serverNow,
    deviceTimeAtVerification: deviceNow,
    lastObservedDeviceTime: deviceNow,
    offlineAccessUntil: _calculateOfflineAccessDeadline(
      serverNow: serverNow,
      subscription: subscription,
    ),
  );

  await _saveOnlineCache(tenantId, tenant, lease);
  _scheduleOfflineAccessRefresh(ref, lease);
  return result;
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
  switch (status) {
    case 'suspended':
      return TenantAccessState.suspended;

    case 'pending_activation':
      return TenantAccessState.activationRequired;

    case 'cancelled':
      return TenantAccessState.cancelled;

    case 'trial_expired':
      return TenantAccessState.trialExpired;

    case 'expired':
      return TenantAccessState.subscriptionExpired;

    case 'trialing':
      if (trialEndsAt != null && !trialEndsAt.isAfter(current)) {
        return TenantAccessState.trialExpired;
      }
      return TenantAccessState.active;

    case 'grace_period':
      if (graceEndsAt != null && !graceEndsAt.isAfter(current)) {
        return TenantAccessState.graceExpired;
      }
      return TenantAccessState.active;

    case 'active':
      if (expiresAt != null && !expiresAt.isAfter(current)) {
        return TenantAccessState.subscriptionExpired;
      }
      return TenantAccessState.active;

    default:
      debugPrint('Unknown subscription status received: $status');
      return TenantAccessState.accessConfigurationError;
  }
}

Future<Map<String, dynamic>?> _loadCachedProfile(String userId) async {
  try {
    return await OfflineStore.loadProfile(userId);
  } catch (error) {
    debugPrint('Cached tenant profile could not be loaded: $error');
    return null;
  }
}

Future<void> _saveOnlineCache(
  String tenantId,
  Map<String, dynamic> tenant,
  _TenantAccessLease lease,
) async {
  try {
    await OfflineStore.saveTenant(tenantId, tenant);
  } catch (error) {
    debugPrint('Tenant cache could not be saved: $error');
  }

  try {
    await _saveAccessLease(tenantId, lease);
  } catch (error) {
    // A local persistence failure must not discard a verified online result.
    debugPrint('Tenant access lease could not be saved: $error');
  }
}

Future<DateTime> _loadServerUtcNow(SupabaseClient client) async {
  final result = await client
      .rpc('get_server_utc_now')
      .timeout(Network.networkTimeout);

  final parsed = DateTime.tryParse(result.toString());

  if (parsed == null) {
    throw const FormatException('Invalid server time');
  }

  return parsed.toUtc();
}

DateTime _calculateOfflineAccessDeadline({
  required DateTime serverNow,
  required Map<String, dynamic>? subscription,
}) {
  var deadline = serverNow.add(_offlineAccessDuration);

  if (subscription == null) return deadline;

  final status = subscription['status']?.toString().toLowerCase();

  final subscriptionDeadline = switch (status) {
    'trialing' => _date(subscription['trial_ends_at']),
    'grace_period' => _date(subscription['grace_ends_at']),
    _ => _date(subscription['expires_at']),
  };

  if (subscriptionDeadline != null && subscriptionDeadline.isBefore(deadline)) {
    deadline = subscriptionDeadline;
  }

  return deadline;
}

Future<TenantAccessState> _resolveOfflineAccess(String tenantId) async {
  final lease = await _loadAccessLease(tenantId);

  if (lease == null) {
    return TenantAccessState.offlineVerificationRequired;
  }

  // Last online verification mein account blocked tha.
  // Offline mode usay dobara active nahi bana sakta.
  if (lease.state != TenantAccessState.active) {
    return lease.state;
  }

  final deviceNow = DateTime.now().toUtc();

  final rollbackBoundary = lease.lastObservedDeviceTime.subtract(
    _allowedClockRollback,
  );

  if (deviceNow.isBefore(rollbackBoundary)) {
    debugPrint(
      'Device clock rollback detected. '
      'Previous=${lease.lastObservedDeviceTime}, Current=$deviceNow',
    );

    return TenantAccessState.offlineVerificationRequired;
  }

  // A small clock correction uses the previous maximum observed time.
  // Effective time kabhi backwards nahi jayega.
  final effectiveDeviceNow =
      deviceNow.isAfter(lease.lastObservedDeviceTime)
          ? deviceNow
          : lease.lastObservedDeviceTime;

  final elapsedSinceVerification = effectiveDeviceNow.difference(
    lease.deviceTimeAtVerification,
  );

  final estimatedServerNow = lease.serverVerifiedAt.add(
    elapsedSinceVerification,
  );

  // Persist the maximum even when the lease has expired. Otherwise a user can
  // move the clock forward, trigger expiry, then move it back and reuse it.
  await _saveAccessLeaseBestEffort(
    tenantId,
    lease.copyWith(lastObservedDeviceTime: effectiveDeviceNow),
  );

  if (!estimatedServerNow.isBefore(lease.offlineAccessUntil)) {
    return TenantAccessState.offlineVerificationRequired;
  }

  return TenantAccessState.active;
}

Future<TenantAccessState> _resolveOfflineAccessAndSchedule(
  Ref ref,
  String tenantId,
) async {
  final result = await _resolveOfflineAccess(tenantId);
  if (result != TenantAccessState.active) return result;

  final lease = await _loadAccessLease(tenantId);
  if (lease != null) _scheduleOfflineAccessRefresh(ref, lease);
  return result;
}

Future<void> _saveAccessLease(String tenantId, _TenantAccessLease lease) async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.setString(
    'offline.tenant_access_lease.$tenantId',
    jsonEncode(lease.toJson()),
  );
}

Future<void> _saveAccessLeaseBestEffort(
  String tenantId,
  _TenantAccessLease lease,
) async {
  try {
    await _saveAccessLease(tenantId, lease);
  } catch (error) {
    debugPrint('Tenant access lease update failed: $error');
  }
}

Future<_TenantAccessLease?> _loadAccessLease(String tenantId) async {
  final prefs = await SharedPreferences.getInstance();

  final raw = prefs.getString('offline.tenant_access_lease.$tenantId');

  if (raw == null) return null;

  try {
    final decoded = jsonDecode(raw);

    if (decoded is! Map) return null;

    return _TenantAccessLease.fromJson(Map<String, dynamic>.from(decoded));
  } catch (error) {
    debugPrint('Invalid tenant access lease: $error');
    return null;
  }
}

void _scheduleOfflineAccessRefresh(Ref ref, _TenantAccessLease lease) {
  if (lease.state != TenantAccessState.active) return;

  final deviceNow = DateTime.now().toUtc();

  if (deviceNow.isBefore(
    lease.lastObservedDeviceTime.subtract(_allowedClockRollback),
  )) {
    return;
  }

  final effectiveDeviceNow =
      deviceNow.isAfter(lease.lastObservedDeviceTime)
          ? deviceNow
          : lease.lastObservedDeviceTime;

  final elapsed = effectiveDeviceNow.difference(lease.deviceTimeAtVerification);

  final estimatedServerNow = lease.serverVerifiedAt.add(elapsed);

  final delay = lease.offlineAccessUntil.difference(estimatedServerNow);

  if (delay <= Duration.zero) return;

  final timer = Timer(delay, () {
    ref.invalidate(tenantAccessProvider);
    ref.read(tenantAccessRefreshProvider).refresh();
  });

  ref.onDispose(timer.cancel);
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}
