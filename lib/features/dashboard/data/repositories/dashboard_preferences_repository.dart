import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/offline/offline_store.dart';

class DashboardPreferences {
  final String userId;
  final String tenantId;
  final String branchId;
  final List<String> accountIds;

  const DashboardPreferences({
    required this.userId,
    required this.tenantId,
    required this.branchId,
    this.accountIds = const [],
  });
}

class DashboardPreferencesRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);
  static const _mutationType = 'upsert_dashboard_preferences';
  final SupabaseClient _client;

  DashboardPreferencesRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  Future<DashboardPreferences> load(String branchId) async {
    final tenantId = await _tenantId();
    final cached = await _loadLocal(tenantId, branchId);
    try {
      await syncOfflineMutations();
      final row = await _client
          .from('user_branch_dashboard_preferences')
          .select('selected_account_ids')
          .eq('user_id', _currentUser.id)
          .eq('tenant_id', tenantId)
          .eq('branch_id', branchId)
          .maybeSingle()
          .timeout(_networkTimeout);
      final preferences = DashboardPreferences(
        userId: _currentUser.id,
        tenantId: tenantId,
        branchId: branchId,
        accountIds: _accountIds(row?['selected_account_ids']),
      );
      await _saveLocal(preferences);
      return preferences;
    } catch (_) {
      return cached ??
          DashboardPreferences(
            userId: _currentUser.id,
            tenantId: tenantId,
            branchId: branchId,
          );
    }
  }

  Future<void> save({
    required String branchId,
    required List<String> accountIds,
  }) async {
    final uniqueIds = accountIds.toSet().take(2).toList();
    if (uniqueIds.isEmpty) {
      throw Exception('Select at least one dashboard account.');
    }
    final tenantId = await _tenantId();
    final preferences = DashboardPreferences(
      userId: _currentUser.id,
      tenantId: tenantId,
      branchId: branchId,
      accountIds: uniqueIds,
    );
    await _saveLocal(preferences);
    final payload = _payload(preferences);
    try {
      await _client
          .from('user_branch_dashboard_preferences')
          .upsert(payload, onConflict: 'user_id,branch_id')
          .timeout(_networkTimeout);
    } catch (error) {
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: _mutationType,
        payload: payload,
      );
      debugPrint('Dashboard preferences queued offline: $error');
    }
  }

  Future<void> syncOfflineMutations() async {
    final userId = _currentUser.id;
    final mutations = await OfflineStore.loadMutations(userId);
    if (mutations.isEmpty) return;
    final remaining = <OfflineMutation>[];
    Object? syncError;
    for (final mutation in mutations) {
      if (mutation.type != _mutationType) {
        remaining.add(mutation);
        continue;
      }
      try {
        await _client
            .from('user_branch_dashboard_preferences')
            .upsert(mutation.payload, onConflict: 'user_id,branch_id');
      } catch (error) {
        remaining.add(mutation);
        syncError ??= error;
      }
    }
    await OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: mutations,
      remaining: remaining,
    );
    if (syncError != null) {
      throw Exception('Dashboard settings not synced yet.');
    }
  }

  Future<String> _tenantId() async {
    final profile = await OfflineStore.loadProfile(_currentUser.id);
    final tenantId = profile?['tenant_id'] as String?;
    if (tenantId == null) throw Exception('Tenant not found');
    return tenantId;
  }

  Map<String, dynamic> _payload(DashboardPreferences preferences) => {
    'user_id': _currentUser.id,
    'tenant_id': preferences.tenantId,
    'branch_id': preferences.branchId,
    'selected_account_ids': preferences.accountIds,
    'updated_at': DateTime.now().toIso8601String(),
  };

  Future<DashboardPreferences?> _loadLocal(
    String tenantId,
    String branchId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(tenantId, branchId));
    if (raw == null) return null;
    return DashboardPreferences(
      userId: _currentUser.id,
      tenantId: tenantId,
      branchId: branchId,
      accountIds: _accountIds(jsonDecode(raw)),
    );
  }

  Future<void> _saveLocal(DashboardPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(preferences.tenantId, preferences.branchId),
      jsonEncode(preferences.accountIds),
    );
  }

  String _cacheKey(String tenantId, String branchId) =>
      'dashboard_accounts_${_currentUser.id}_${tenantId}_$branchId';

  List<String> _accountIds(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toSet().take(2).toList();
  }
}
