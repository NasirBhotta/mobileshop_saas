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
  offlineVerificationRequired;

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

    final lease = await _createVerifiedAccessLease(
      client: client,
      tenantId: tenantId,
      state: result,
      subscription: subscription,
    );

    _scheduleDeadlineRefresh(ref, subscription);

    if (lease != null) {
      _scheduleOfflineAccessRefresh(ref, lease);
    }

    return result;
  } catch (_) {
    final result = await _resolveOfflineAccess(tenantId);

    final lease = await _loadAccessLease(tenantId);

    if (result == TenantAccessState.active && lease != null) {
      _scheduleOfflineAccessRefresh(ref, lease);
    }

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

Future<_TenantAccessLease?> _createVerifiedAccessLease({
  required SupabaseClient client,
  required String tenantId,
  required TenantAccessState state,
  required Map<String, dynamic>? subscription,
}) async {
  final deviceNow = DateTime.now().toUtc();

  DateTime serverNow;

  try {
    serverNow = await _loadServerUtcNow(client);
  } catch (error) {
    // Active tenant ke liye untrusted device time se new lease issue nahi karni.
    if (state == TenantAccessState.active) {
      debugPrint(
        'Offline access lease not renewed: server time unavailable ($error)',
      );
      return null;
    }

    // Server ne tenant blocked confirm kar diya hai.
    // Blocked state ko local time ke bawajood save karna safe hai.
    serverNow = deviceNow;
  }

  final offlineAccessUntil = _calculateOfflineAccessDeadline(
    serverNow: serverNow,
    subscription: subscription,
  );

  final lease = _TenantAccessLease(
    state: state,
    serverVerifiedAt: serverNow,
    deviceTimeAtVerification: deviceNow,
    lastObservedDeviceTime: deviceNow,
    offlineAccessUntil: offlineAccessUntil,
  );

  await _saveAccessLease(tenantId, lease);
  return lease;
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

  // Time 2–3 minute peeche hua ho to previous maximum time use hoga.
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

  if (!estimatedServerNow.isBefore(lease.offlineAccessUntil)) {
    return TenantAccessState.offlineVerificationRequired;
  }

  await _saveAccessLease(
    tenantId,
    lease.copyWith(lastObservedDeviceTime: effectiveDeviceNow),
  );

  return TenantAccessState.active;
}

Future<void> _saveAccessLease(String tenantId, _TenantAccessLease lease) async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.setString(
    'offline.tenant_access_lease.$tenantId',
    jsonEncode(lease.toJson()),
  );
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
