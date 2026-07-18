import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/offline/offline_store.dart';
import '../../../../core/utils/offline_error_classifier.dart';
import '../models/shop_setup_model.dart';

final setupFlowRepositoryProvider = Provider<SetupFlowRepository>((ref) {
  return SetupFlowRepository();
});

final setupFlowStatusProvider = FutureProvider<SetupFlowStatus>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) throw Exception('User not logged in');

  return ref.read(setupFlowRepositoryProvider).loadStatus(user.id);
});

final selectedBranchIdProvider = FutureProvider<String>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) throw Exception('User not logged in');

  final status = await ref.watch(setupFlowStatusProvider.future);
  final cachedBranchId = await OfflineStore.loadSelectedBranchId(user.id);
  final profileBranchId = status.profile?['branch_id'] as String?;
  final singleBranchId =
      status.branches.length == 1 ? status.branches.first.id : null;
  final branchIds = {
    for (final branch in status.branches)
      if (branch.id != null) branch.id!,
  };
  final validCachedBranchId =
      cachedBranchId != null && branchIds.contains(cachedBranchId)
          ? cachedBranchId
          : null;
  final validProfileBranchId =
      profileBranchId != null && branchIds.contains(profileBranchId)
          ? profileBranchId
          : null;
  final branchId =
      validCachedBranchId ?? validProfileBranchId ?? singleBranchId;
  if (branchId == null || branchId.isEmpty) {
    throw Exception('Branch select karein');
  }
  return branchId;
});

enum SetupRouteTarget { setup, branchSelection, dashboard }

class SetupFlowStatus {
  final SetupRouteTarget target;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? tenant;
  final List<BranchInputModel> branches;

  const SetupFlowStatus({
    required this.target,
    this.profile,
    this.tenant,
    this.branches = const [],
  });
}

class SetupFlowRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);
  final SupabaseClient _client;

  SetupFlowRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<void> ensureUserProfile({
    required User user,
    String? fullName,
    String? phone,
  }) async {
    final existing =
        await _client
            .from('users')
            .select('id')
            .eq('id', user.id)
            .maybeSingle();

    if (existing != null) return;

    await _client.from('users').insert({
      'id': user.id,
      'full_name': fullName ?? user.userMetadata?['full_name'] ?? '',
      'email': user.email ?? '',
      'phone': phone ?? user.userMetadata?['phone'] ?? '',
      'role': 'owner',
    });
  }

  Future<SetupFlowStatus> loadStatus(String userId) async {
    unawaited(syncOfflineMutations(userId));
    final profile = await loadProfile(userId);

    debugPrint("Profile: $profile");
    final tenantId = profile?['tenant_id'];

    if (profile == null || tenantId == null) {
      return SetupFlowStatus(target: SetupRouteTarget.setup, profile: profile);
    }

    final tenant = await loadTenant(tenantId as String);
    debugPrint("Tenant after upsert: $tenant");

    if (tenant == null) {
      return SetupFlowStatus(target: SetupRouteTarget.setup, profile: profile);
    }

    final branches = await loadBranches(tenantId);
    final requiredBranches = ((tenant['branch_count'] as num?) ?? 1).toInt();
    final setupComplete = tenant['setup_complete'] == true;

    debugPrint(
      "Branches: ${branches.length}, Required: $requiredBranches, Setup Complete: $setupComplete",
    );

    if (!setupComplete) {
      if (branches.length >= requiredBranches) {
        try {
          await markSetupComplete(tenantId).timeout(_networkTimeout);
        } catch (_) {}
      } else {
        return SetupFlowStatus(
          target: SetupRouteTarget.setup,
          profile: profile,
          tenant: tenant,
          branches: branches,
        );
      }
    }
    debugPrint(
      "Branches: ${branches.length}, Required: $requiredBranches, Setup Complete: $setupComplete",
    );
    if (branches.isEmpty) {
      return SetupFlowStatus(
        target: SetupRouteTarget.setup,
        profile: profile,
        tenant: tenant,
        branches: branches,
      );
    }

    if (branches.length == 1) {
      if (profile['branch_id'] != branches.first.id) {
        await selectBranch(userId: userId, branchId: branches.first.id!);
      }
      return SetupFlowStatus(
        target: SetupRouteTarget.dashboard,
        profile: profile,
        tenant: tenant,
        branches: branches,
      );
    }

    final selectedBranchId = profile['branch_id'] as String?;
    final selectedBranchExists = branches.any((b) => b.id == selectedBranchId);

    debugPrint(
      "Selected Branch ID: $selectedBranchId, Exists: $selectedBranchExists",
    );
    return SetupFlowStatus(
      target:
          selectedBranchExists
              ? SetupRouteTarget.dashboard
              : SetupRouteTarget.branchSelection,
      profile: profile,
      tenant: tenant,
      branches: branches,
    );
  }

  Future<Map<String, dynamic>?> loadProfile(String userId) async {
    final cachedProfile = await OfflineStore.loadProfile(userId);
    if (cachedProfile != null) {
      if (cachedProfile['tenant_id'] == null) {
        try {
          final profile = await _remoteProfile(userId).timeout(_networkTimeout);
          if (profile != null) {
            await _saveProfileWithSelectedBranch(userId, profile);
            return profile;
          }
        } catch (_) {
          return cachedProfile;
        }
      }

      unawaited(_refreshProfileCache(userId));
      return cachedProfile;
    }

    try {
      final profile = await _remoteProfile(userId).timeout(_networkTimeout);
      if (profile != null) {
        await _saveProfileWithSelectedBranch(userId, profile);
      }
      return profile;
    } catch (_) {
      return OfflineStore.loadProfile(userId);
    }
  }

  Future<Map<String, dynamic>?> _remoteProfile(String userId) {
    return _client
        .from('users')
        .select('id, tenant_id, branch_id, full_name, email, phone, role')
        .eq('id', userId)
        .maybeSingle();
  }

  Future<void> _refreshProfileCache(String userId) async {
    try {
      final profile = await _remoteProfile(userId).timeout(_networkTimeout);
      if (profile != null) {
        await _saveProfileWithSelectedBranch(userId, profile);
      }
    } catch (_) {}
  }

  Future<void> _saveProfileWithSelectedBranch(
    String userId,
    Map<String, dynamic> profile,
  ) async {
    final selectedBranchId = await OfflineStore.loadSelectedBranchId(userId);
    if (selectedBranchId != null) {
      profile['branch_id'] = selectedBranchId;
    }
    await OfflineStore.saveProfile(userId, profile);
  }

  Future<Map<String, dynamic>?> loadTenant(String tenantId) async {
    final cachedTenant = await OfflineStore.loadTenant(tenantId);
    if (cachedTenant != null) {
      unawaited(_refreshTenantCache(tenantId));
      return cachedTenant;
    }

    try {
      final tenant = await _remoteTenant(tenantId).timeout(_networkTimeout);
      if (tenant != null) await OfflineStore.saveTenant(tenantId, tenant);
      return tenant;
    } catch (_) {
      return OfflineStore.loadTenant(tenantId);
    }
  }

  Future<Map<String, dynamic>?> _remoteTenant(String tenantId) {
    return _client
        .from('tenants')
        .select(
          'id, shop_name, business_type, branch_count, plan, status, setup_complete',
        )
        .eq('id', tenantId)
        .maybeSingle();
  }

  Future<void> _refreshTenantCache(String tenantId) async {
    try {
      final tenant = await _remoteTenant(tenantId).timeout(_networkTimeout);
      if (tenant != null) await OfflineStore.saveTenant(tenantId, tenant);
    } catch (_) {}
  }

  Future<List<BranchInputModel>> loadBranches(String tenantId) async {
    final cachedBranches = await OfflineStore.loadBranches(tenantId);
    if (cachedBranches.isNotEmpty) {
      unawaited(_refreshBranchesCache(tenantId));
      return cachedBranches;
    }

    try {
      return await _fetchRemoteBranches(tenantId).timeout(_networkTimeout);
    } catch (_) {
      return OfflineStore.loadBranches(tenantId);
    }
  }

  Future<List<BranchInputModel>> _fetchRemoteBranches(String tenantId) async {
    final rows = await _client
        .from('branches')
        .select('id, name, address, city')
        .eq('tenant_id', tenantId)
        .order('id');

    final branches =
        (rows as List<dynamic>)
            .map((row) => BranchInputModel.fromMap(row as Map<String, dynamic>))
            .toList();
    await OfflineStore.saveBranches(tenantId, branches);
    return branches;
  }

  Future<void> _refreshBranchesCache(String tenantId) async {
    try {
      await _fetchRemoteBranches(tenantId).timeout(_networkTimeout);
    } catch (_) {}
  }

  Future<String> ensureTenant({
    required User user,
    required String shopName,
    required String businessType,
    required int branchCount,
  }) async {
    await ensureUserProfile(user: user);

    final profile = await loadProfile(user.id);
    final existingTenantId = profile?['tenant_id'] as String?;

    if (existingTenantId != null) {
      final tenant = await loadTenant(existingTenantId);

      if (tenant != null) {
        return existingTenantId;
      }

      // The reference is stale.
      await _client.from('users').update({'tenant_id': null}).eq('id', user.id);
    }

    final tenantId = user.id;

    final result = await _client.from('tenants').upsert({
      'id': tenantId,
      'shop_name': shopName,
      'business_type': businessType,
      'branch_count': branchCount < 1 ? 1 : branchCount,
      'plan': 'starter',
      'status': 'active',
      'setup_complete': false,
    }, onConflict: 'id');

    debugPrint("UPSERT RESULT: $result");
    await _client
        .from('users')
        .update({'tenant_id': tenantId})
        .eq('id', user.id)
        .select();

    final updatedProfile = <String, dynamic>{
      if (profile != null) ...profile,
      'id': user.id,
      'tenant_id': tenantId,
      'branch_id': profile?['branch_id'],
      'full_name':
          profile?['full_name'] ?? user.userMetadata?['full_name'] ?? '',
      'email': profile?['email'] ?? user.email ?? '',
      'phone': profile?['phone'] ?? user.userMetadata?['phone'] ?? '',
      'role': profile?['role'] ?? 'owner',
    };
    await OfflineStore.saveProfile(user.id, updatedProfile);
    await OfflineStore.saveTenant(tenantId, {
      'id': tenantId,
      'shop_name': shopName,
      'business_type': businessType,
      'branch_count': branchCount < 1 ? 1 : branchCount,
      'plan': 'starter',
      'status': 'active',
      'setup_complete': false,
    });

    return tenantId;
  }

  Future<int> countBranches(String tenantId) async {
    return (await loadBranches(tenantId)).length;
  }

  Future<int> createNextBranch({
    required String tenantId,
    required int branchCount,
    required BranchInputModel branch,
  }) async {
    final existingBranches = await _fetchRemoteBranches(
      tenantId,
    ).timeout(_networkTimeout);
    final existingCount = existingBranches.length;
    if (existingCount >= branchCount) return existingCount;

    await _client.from('branches').insert({
      'tenant_id': tenantId,
      'name':
          branch.name.trim().isEmpty
              ? 'Branch ${existingCount + 1}'
              : branch.name.trim(),
      'address': branch.address.trim(),
      'city': branch.city.trim(),
      'is_active': true,
    });

    final updatedBranches = await _fetchRemoteBranches(
      tenantId,
    ).timeout(_networkTimeout);
    return updatedBranches.length;
  }

  Future<void> markSetupComplete(String tenantId) async {
    await _client
        .from('tenants')
        .update({'setup_complete': true})
        .eq('id', tenantId);

    final tenant = await loadTenant(tenantId);
    if (tenant != null) {
      await OfflineStore.saveTenant(tenantId, {
        ...tenant,
        'setup_complete': true,
      });
    }
  }

  Future<void> selectBranch({
    required String userId,
    required String branchId,
  }) async {
    final profile = await loadProfile(userId);
    final tenantId = profile?['tenant_id'] as String?;
    if (tenantId == null) throw Exception('Tenant setup required');

    final tenantBranches = await loadBranches(tenantId);
    final belongsToTenant = tenantBranches.any(
      (branch) => branch.id == branchId,
    );
    if (!belongsToTenant) {
      throw Exception('Selected branch must belong to user tenant');
    }

    try {
      await _client
          .from('users')
          .update({'branch_id': branchId})
          .eq('id', userId)
          .timeout(_networkTimeout);
      await OfflineStore.selectBranch(userId: userId, branchId: branchId);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.selectBranch(userId: userId, branchId: branchId);
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'select_branch',
        payload: {'user_id': userId, 'branch_id': branchId},
      );
    }
  }

  Future<void> syncOfflineMutations(String userId) async {
    final mutations = await OfflineStore.loadMutations(userId);
    if (mutations.isEmpty) return;

    final remaining = <OfflineMutation>[];
    for (final mutation in mutations) {
      if (mutation.type != 'select_branch') {
        remaining.add(mutation);
        continue;
      }

      try {
        await _client
            .from('users')
            .update({'branch_id': mutation.payload['branch_id']})
            .eq('id', mutation.payload['user_id'])
            .timeout(_networkTimeout);
      } catch (_) {
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutations(userId, remaining);
  }
}
