import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReceiptSettingsRepository {
  static const _networkTimeout = Duration(milliseconds: 1500);

  final SupabaseClient _client;

  ReceiptSettingsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  String? get _currentUserId => _client.auth.currentUser?.id;

  Future<Map<String, dynamic>?> _currentProfile() async {
    final userId = _currentUserId;
    if (userId == null) return null;

    final cached = await OfflineStore.loadProfile(userId);
    if (cached != null) {
      unawaited(_refreshProfile(userId));
      return cached;
    }
    return await _refreshProfile(userId);
  }

  Future<Map<String, dynamic>?> _refreshProfile(String userId) async {
    try {
      final remote = await _client
          .from('users')
          .select('id, tenant_id, full_name, phone, role')
          .eq('id', userId)
          .maybeSingle()
          .timeout(_networkTimeout);
      if (remote != null) {
        await OfflineStore.saveProfile(userId, remote);
        return remote;
      }
    } catch (_) {}
    return await OfflineStore.loadProfile(userId);
  }

  Future<String> _currentTenantId() async {
    try {
      final profile = await _currentProfile();
      final tenantId = profile?['tenant_id'] as String?;
      if (tenantId != null && tenantId.isNotEmpty) {
        return tenantId;
      }
    } catch (_) {}

    // Fallback search in local database
    try {
      final userId = _currentUserId;
      if (userId != null) {
        final profile = await LocalStore.loadProfile(userId);
        final tenantId = profile?['tenant_id'] as String?;
        if (tenantId != null && tenantId.isNotEmpty) {
          return tenantId;
        }
      }
    } catch (_) {}

    return 'default_tenant';
  }

  Future<Map<String, dynamic>?> _tenantInfo(String tenantId) async {
    final cached = await OfflineStore.loadTenant(tenantId);
    if (cached != null) return cached;
    try {
      final remote = await _client
          .from('tenants')
          .select()
          .eq('id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);
      if (remote != null) {
        await OfflineStore.saveTenant(tenantId, remote);
        return remote;
      }
    } catch (_) {}
    return null;
  }

  Future<ReceiptConfigurationModel> loadReceiptConfig() async {
    final tenantId = await _currentTenantId();
    final tenant = await _tenantInfo(tenantId);
    final shopName = tenant?['shop_name']?.toString() ?? 'Mobile Care & Services';
    final shopPhone = tenant?['phone']?.toString();
    final shopAddress = tenant?['address']?.toString();

    // 1. Check local cache (SQLite + SharedPreferences)
    final cachedConfig = await OfflineStore.loadReceiptConfig(tenantId);
    if (cachedConfig != null) {
      unawaited(syncOfflineMutations());
      unawaited(_refreshReceiptConfig(tenantId, shopName, shopPhone, shopAddress));
      return ReceiptConfigurationModel.fromMap(cachedConfig);
    }

    // 2. Fetch remote if no local cache
    try {
      final remoteSettings = await _client
          .from('tenant_settings')
          .select()
          .eq('tenant_id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);

      if (remoteSettings != null) {
        final rawConfig = remoteSettings['receipt_config'];
        if (rawConfig != null) {
          final map = rawConfig is Map
              ? Map<String, dynamic>.from(rawConfig)
              : Map<String, dynamic>.from(jsonDecode(rawConfig.toString()) as Map);
          await OfflineStore.saveReceiptConfig(tenantId, map);
          return ReceiptConfigurationModel.fromMap(map);
        } else if (remoteSettings['receipt_footer'] != null) {
          final fallbackConfig = ReceiptConfigurationModel.defaultConfig(
            shopName: shopName,
            phone: shopPhone,
            address: shopAddress,
          ).copyWith(
            footerMessage: remoteSettings['receipt_footer']?.toString(),
          );
          await OfflineStore.saveReceiptConfig(tenantId, fallbackConfig.toMap());
          return fallbackConfig;
        }
      }
    } catch (e) {
      debugPrint('Receipt settings remote load info: $e');
    }

    // 3. Default fallback
    final defaultConfig = ReceiptConfigurationModel.defaultConfig(
      shopName: shopName,
      phone: shopPhone,
      address: shopAddress,
    );
    await OfflineStore.saveReceiptConfig(tenantId, defaultConfig.toMap());
    return defaultConfig;
  }

  Future<void> _refreshReceiptConfig(
    String tenantId,
    String shopName,
    String? shopPhone,
    String? shopAddress,
  ) async {
    try {
      final remoteSettings = await _client
          .from('tenant_settings')
          .select()
          .eq('tenant_id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);

      if (remoteSettings != null && remoteSettings['receipt_config'] != null) {
        final rawConfig = remoteSettings['receipt_config'];
        final map = rawConfig is Map
            ? Map<String, dynamic>.from(rawConfig)
            : Map<String, dynamic>.from(jsonDecode(rawConfig.toString()) as Map);
        await OfflineStore.saveReceiptConfig(tenantId, map);
      }
    } catch (_) {}
  }

  Future<void> saveReceiptConfig(ReceiptConfigurationModel config) async {
    final tenantId = await _currentTenantId();
    final updatedConfig = config.copyWith(updatedAt: DateTime.now());
    final configMap = updatedConfig.toMap();

    // 1. Save locally first (instant UI update & offline durability)
    await OfflineStore.saveReceiptConfig(tenantId, configMap);

    // 2. Prepare payload for sync
    final settingsPayload = {
      'tenant_id': tenantId,
      'receipt_footer': updatedConfig.footerMessage,
      'receipt_config': jsonEncode(configMap),
      'updated_at': DateTime.now().toIso8601String(),
    };

    // 3. Attempt remote update
    try {
      await _client
          .from('tenant_settings')
          .upsert(settingsPayload, onConflict: 'tenant_id')
          .timeout(_networkTimeout);
    } catch (e) {
      debugPrint('Receipt config remote upsert failed (queued for background sync): $e');
      final userId = _currentUserId;
      if (userId != null) {
        try {
          await OfflineStore.enqueueMutation(
            userId: userId,
            type: 'update_receipt_config',
            payload: {
              'tenant_id': tenantId,
              'settings': settingsPayload,
              'config': configMap,
            },
          );
        } catch (_) {}
      }
    }
  }

  Future<ReceiptConfigurationModel> resetToDefault() async {
    final tenantId = await _currentTenantId();
    final tenant = await _tenantInfo(tenantId);
    final shopName = tenant?['shop_name']?.toString() ?? 'Mobile Care & Services';
    final shopPhone = tenant?['phone']?.toString();
    final shopAddress = tenant?['address']?.toString();

    final defaultConfig = ReceiptConfigurationModel.defaultConfig(
      shopName: shopName,
      phone: shopPhone,
      address: shopAddress,
    );

    await saveReceiptConfig(defaultConfig);
    return defaultConfig;
  }

  Future<void> syncOfflineMutations() async {
    final userId = _currentUserId;
    if (userId == null) return;

    final mutations = await OfflineStore.loadMutations(userId);
    final receiptMutations = mutations.where((m) => m.type == 'update_receipt_config').toList();
    if (receiptMutations.isEmpty) return;

    final remaining = <OfflineMutation>[];
    final random = Random();

    for (var i = 0; i < mutations.length; i++) {
      final mutation = mutations[i];
      if (mutation.type != 'update_receipt_config') {
        remaining.add(mutation);
        continue;
      }

      try {
        final payload = mutation.payload;
        final settings = Map<String, dynamic>.from(payload['settings'] as Map);

        // Exponential backoff with random jitter before network call if retrying
        final jitterMs = random.nextInt(150);
        if (jitterMs > 0) {
          await Future.delayed(Duration(milliseconds: jitterMs));
        }

        await _client
            .from('tenant_settings')
            .upsert(settings, onConflict: 'tenant_id')
            .timeout(_networkTimeout);
      } catch (e) {
        debugPrint('Receipt config mutation sync retry: $e');
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: mutations,
      remaining: remaining,
    );
  }
}
