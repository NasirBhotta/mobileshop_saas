import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/offline/offline_store.dart';
import '../../../../core/authorization/permission_provider.dart';
import '../../../../core/utils/offline_error_classifier.dart';
import '../models/shop_setup_model.dart';

final setupFlowRepositoryProvider = Provider<SetupFlowRepository>((ref) {
  return SetupFlowRepository();
});

final setupFlowStatusProvider = FutureProvider<SetupFlowStatus>((ref) async {
  ref.watch(permissionRevisionProvider);
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) throw Exception('User not logged in');

  final repository = ref.read(setupFlowRepositoryProvider);
  final status = await repository.loadStatus(user.id);
  return repository.restrictToAccessibleBranches(user.id, status);
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

enum AccountIdentityState { active, revoked, offline }

class AccountIdentityResult {
  final AccountIdentityState state;

  const AccountIdentityResult(this.state);
}

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

SetupFlowStatus filterSetupStatusForBranchAccess(
  SetupFlowStatus status, {
  required bool configured,
  required Set<String> accessibleBranchIds,
}) {
  if (!configured) return status;
  final branches = status.branches
      .where((branch) => accessibleBranchIds.contains(branch.id))
      .toList(growable: false);
  final selectedBranchId = status.profile?['branch_id'] as String?;
  final selectedBranchExists = branches.any(
    (branch) => branch.id == selectedBranchId,
  );
  return SetupFlowStatus(
    target:
        selectedBranchExists
            ? SetupRouteTarget.dashboard
            : SetupRouteTarget.branchSelection,
    profile: status.profile,
    tenant: status.tenant,
    branches: branches,
  );
}

class SetupFlowRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);
  static const _identityTimeout = Duration(seconds: 5);
  final SupabaseClient _client;
  final Map<String, Future<void>> _syncsInFlight = {};
  final Set<String> _syncAgainForUsers = {};

  SetupFlowRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<AccountIdentityResult> validateCurrentAccount(String userId) async {
    final hasCachedProfile = await OfflineStore.loadProfile(userId) != null;
    final maxAttempts = hasCachedProfile ? 1 : 4;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final raw = await _client
            .rpc('current_account_context')
            .timeout(_identityTimeout);
        final context =
            raw is Map
                ? Map<String, dynamic>.from(raw)
                : const <String, dynamic>{};
        final exists = context['exists'] == true;
        final isActive = context['is_active'] == true;

        if (exists && isActive && context['id'] == userId) {
          await OfflineStore.saveProfile(userId, context);
          return const AccountIdentityResult(AccountIdentityState.active);
        }

        // A brand-new auth session can be emitted just before the signup flow
        // finishes provisioning public.users. Retry only when there is no
        // established local profile; a known account disappearing is an
        // immediate revocation signal.
        if (!hasCachedProfile && attempt + 1 < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }

        return const AccountIdentityResult(AccountIdentityState.revoked);
      } catch (error) {
        OfflineErrorClassifier.rethrowIfTerminal(error);
        if (!hasCachedProfile && attempt + 1 < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        return const AccountIdentityResult(AccountIdentityState.offline);
      }
    }

    return const AccountIdentityResult(AccountIdentityState.revoked);
  }

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
    final profile = await loadProfile(userId);

    final tenantId = profile?['tenant_id'];

    if (profile == null || tenantId == null) {
      return SetupFlowStatus(target: SetupRouteTarget.setup, profile: profile);
    }

    final tenant = await loadTenant(tenantId as String);

    if (tenant == null) {
      return SetupFlowStatus(target: SetupRouteTarget.setup, profile: profile);
    }

    final branches = await loadBranches(tenantId);
    final requiredBranches = ((tenant['branch_count'] as num?) ?? 1).toInt();
    final setupComplete = tenant['setup_complete'] == true;

    if (!setupComplete || branches.length < requiredBranches) {
      return SetupFlowStatus(
        target: SetupRouteTarget.setup,
        profile: profile,
        tenant: tenant,
        branches: branches,
      );
    }
    if (branches.isEmpty) {
      return SetupFlowStatus(
        target: SetupRouteTarget.setup,
        profile: profile,
        tenant: tenant,
        branches: branches,
      );
    }

    if (branches.length == 1) {
      return SetupFlowStatus(
        target:
            profile['branch_id'] == branches.first.id
                ? SetupRouteTarget.dashboard
                : SetupRouteTarget.branchSelection,
        profile: profile,
        tenant: tenant,
        branches: branches,
      );
    }

    final selectedBranchId = profile['branch_id'] as String?;
    final selectedBranchExists = branches.any((b) => b.id == selectedBranchId);

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

  Future<SetupFlowStatus> restrictToAccessibleBranches(
    String userId,
    SetupFlowStatus status,
  ) async {
    final tenantId = status.profile?['tenant_id'] as String?;
    if (tenantId == null ||
        status.target == SetupRouteTarget.setup ||
        status.profile?['role'] == 'owner') {
      return status;
    }

    late final bool configured;
    late final Set<String> accessibleIds;
    try {
      final rows = await _client
          .from('user_branch_role_assignments')
          .select('branch_id, revoked_at')
          .eq('tenant_id', tenantId)
          .eq('user_id', userId)
          .timeout(_networkTimeout);
      configured = rows.isNotEmpty;
      accessibleIds = {
        for (final row in rows)
          if (row['revoked_at'] == null) row['branch_id'] as String,
      };
      await OfflineStore.saveBranchAccess(
        userId,
        configured: configured,
        branchIds: accessibleIds,
      );
    } catch (_) {
      final cached = await OfflineStore.loadBranchAccess(userId);
      if (cached == null) return status;
      configured = cached['configured'] == true;
      accessibleIds = Set<String>.from(
        cached['branch_ids'] as List? ?? const [],
      );
    }

    return filterSetupStatusForBranchAccess(
      status,
      configured: configured,
      accessibleBranchIds: accessibleIds,
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
    final serverBranchId = profile['branch_id'] as String?;

    if (serverBranchId != null && serverBranchId.isNotEmpty) {
      await OfflineStore.selectBranch(userId: userId, branchId: serverBranchId);
    }

    await OfflineStore.saveProfile(userId, Map<String, dynamic>.from(profile));
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
        .eq('is_active', true)
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

      final staleLinkCleared = await _client
          .rpc('clear_stale_tenant_link')
          .timeout(_networkTimeout);
      if (staleLinkCleared != true) {
        throw StateError(
          'Tenant exists but is not accessible to the current session',
        );
      }
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
    await _client.rpc(
      'complete_tenant_setup',
      params: {'p_tenant_id': tenantId},
    );

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
    final accessibleStatus = await restrictToAccessibleBranches(
      userId,
      await loadStatus(userId),
    );
    if (!accessibleStatus.branches.any((branch) => branch.id == branchId)) {
      throw Exception('Selected branch is not assigned to this user.');
    }

    bool belongsToTenant;
    try {
      final branch = await _client
          .from('branches')
          .select('id')
          .eq('id', branchId)
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .maybeSingle()
          .timeout(_networkTimeout);
      belongsToTenant = branch != null;
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);

      // Offline selection uses the last successfully synchronized snapshot.
      final cachedBranches = await OfflineStore.loadBranches(tenantId);
      belongsToTenant = cachedBranches.any((branch) => branch.id == branchId);
    }
    if (!belongsToTenant) {
      throw Exception(
        'Selected branch is invalid, inactive, or does not belong to this tenant',
      );
    }

    try {
      await _client
          .from('users')
          .update({'branch_id': branchId})
          .eq('id', userId)
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.selectBranch(userId: userId, branchId: branchId);
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'select_branch',
        payload: {'user_id': userId, 'branch_id': branchId},
      );
      return;
    }

    await OfflineStore.selectBranch(userId: userId, branchId: branchId);
  }

  Future<void> syncOfflineMutations(String userId) async {
    final mutations = await OfflineStore.loadMutations(userId);
    if (mutations.isEmpty) return;

    for (final mutation in mutations) {
      if (mutation.type != 'select_branch') continue;

      final branchId = mutation.payload['branch_id'];
      if (branchId is! String || branchId.trim().isEmpty) {
        debugPrint('Removing invalid select_branch mutation: ${mutation.id}');
        await OfflineStore.removeMutation(
          userId: userId,
          mutationId: mutation.id,
        );
        continue;
      }

      try {
        final profile = await _remoteProfile(userId).timeout(_networkTimeout);
        final tenantId = profile?['tenant_id'];
        if (tenantId is! String || tenantId.isEmpty) {
          throw StateError('Mutation user has no tenant');
        }

        final branch = await _client
            .from('branches')
            .select('id')
            .eq('id', branchId)
            .eq('tenant_id', tenantId)
            .eq('is_active', true)
            .maybeSingle()
            .timeout(_networkTimeout);
        if (branch == null) {
          throw StateError(
            'Mutation branch is invalid, inactive, or belongs to another tenant',
          );
        }

        final updated = await _client
            .from('users')
            .update({'branch_id': branchId})
            .eq('id', userId)
            .select('id')
            .maybeSingle()
            .timeout(_networkTimeout);
        if (updated == null) {
          throw StateError('Branch selection update affected no user row');
        }

        await OfflineStore.removeMutation(
          userId: userId,
          mutationId: mutation.id,
        );
      } catch (error) {
        debugPrint('Mutation ${mutation.id} sync failed: $error');
        if (OfflineErrorClassifier.isRetryable(error)) {
          // Keep transient failures queued for the next sync attempt.
          continue;
        }

        // A permanently invalid mutation must not poison the rest of the
        // queue. RLS/database failures are terminal according to the shared
        // classifier and are discarded here after being logged.
        await OfflineStore.removeMutation(
          userId: userId,
          mutationId: mutation.id,
        );
        debugPrint('Removed permanently failed mutation ${mutation.id}');
      }
    }
  }

  Future<void> requestOfflineMutationSync(String userId) {
    final running = _syncsInFlight[userId];
    if (running != null) {
      _syncAgainForUsers.add(userId);
      return running;
    }

    final future = _runOfflineMutationSyncLoop(userId);
    _syncsInFlight[userId] = future;
    return future.whenComplete(() {
      if (identical(_syncsInFlight[userId], future)) {
        _syncsInFlight.remove(userId);
        _syncAgainForUsers.remove(userId);
      }
    });
  }

  Future<void> _runOfflineMutationSyncLoop(String userId) async {
    do {
      _syncAgainForUsers.remove(userId);
      await syncOfflineMutations(userId);
    } while (_syncAgainForUsers.contains(userId));
  }
}
