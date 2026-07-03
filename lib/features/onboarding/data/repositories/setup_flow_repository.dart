import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shop_setup_model.dart';

final setupFlowRepositoryProvider = Provider<SetupFlowRepository>((ref) {
  return SetupFlowRepository();
});

final setupFlowStatusProvider = FutureProvider<SetupFlowStatus>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) throw Exception('User not logged in');

  return ref.read(setupFlowRepositoryProvider).loadStatus(user.id);
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
        await markSetupComplete(tenantId);
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
    if (branches.length <= 1) {
      if (branches.length == 1 && profile['branch_id'] != branches.first.id) {
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

  Future<Map<String, dynamic>?> loadProfile(String userId) {
    return _client
        .from('users')
        .select('id, tenant_id, branch_id, full_name, email, phone, role')
        .eq('id', userId)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> loadTenant(String tenantId) {
    return _client
        .from('tenants')
        .select(
          'id, shop_name, business_type, branch_count, plan, status, setup_complete',
        )
        .eq('id', tenantId)
        .maybeSingle();
  }

  Future<List<BranchInputModel>> loadBranches(String tenantId) async {
    final rows = await _client
        .from('branches')
        .select('id, name, address, city')
        .eq('tenant_id', tenantId)
        .order('id');

    return (rows as List<dynamic>)
        .map((row) => BranchInputModel.fromMap(row as Map<String, dynamic>))
        .toList();
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
    final existingCount = await countBranches(tenantId);
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

    return countBranches(tenantId);
  }

  Future<void> markSetupComplete(String tenantId) {
    return _client
        .from('tenants')
        .update({'setup_complete': true})
        .eq('id', tenantId);
  }

  Future<void> selectBranch({
    required String userId,
    required String branchId,
  }) {
    return _client
        .from('users')
        .update({'branch_id': branchId})
        .eq('id', userId);
  }
}
