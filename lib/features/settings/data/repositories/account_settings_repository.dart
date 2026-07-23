import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/features/onboarding/data/models/shop_setup_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountSettingsData {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> tenant;
  final List<BranchInputModel> branches;
  final String? selectedBranchId;

  const AccountSettingsData({
    required this.profile,
    required this.tenant,
    required this.branches,
    required this.selectedBranchId,
  });

  String get userId => profile['id'] as String;
  String get tenantId => tenant['id'] as String;
  String get fullName => profile['full_name'] as String? ?? '';
  String get email => profile['email'] as String? ?? '';
  String get phone => profile['phone'] as String? ?? '';
  String get role => profile['role'] as String? ?? '';
  String get shopName => tenant['shop_name'] as String? ?? '';
  String get businessType => tenant['business_type'] as String? ?? '';
  int get branchCount => (tenant['branch_count'] as num?)?.toInt() ?? 1;
  String get plan => tenant['plan'] as String? ?? 'starter';
  String get status => tenant['status'] as String? ?? 'active';

  bool get isStarterPlan => plan.toLowerCase() == 'starter';
  bool get isBusinessPlan => plan.toLowerCase() == 'business';
  bool get isEnterprisePlan => plan.toLowerCase() == 'enterprise';

  bool get canExportReports => isBusinessPlan || isEnterprisePlan;
  bool get canScheduleReports => isBusinessPlan || isEnterprisePlan;
  bool get canUseMultiBranchAnalytics => isBusinessPlan || isEnterprisePlan;
  bool get canUseAdvancedReports => isBusinessPlan || isEnterprisePlan;

  String get planLabel {
    switch (plan.toLowerCase()) {
      case 'business':
        return 'Business';
      case 'enterprise':
        return 'Enterprise';
      case 'starter':
      default:
        return 'Starter';
    }
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'suspended':
        return 'Suspended';
      case 'active':
      default:
        return 'Active';
    }
  }
}

class AccountSettingsRepository {
  static const _networkTimeout = Duration(milliseconds: 1200);

  final SupabaseClient _client = Supabase.instance.client;

  User get _currentUser {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user;
  }

  Future<AccountSettingsData> loadSettings({bool refreshTenant = false}) async {
    unawaited(syncOfflineMutations());

    final profile = await _loadProfile();
    final tenantId = profile['tenant_id'] as String?;
    if (tenantId == null) throw Exception('Shop setup not found');

    final tenant = await _loadTenant(tenantId, preferRemote: refreshTenant);
    if (tenant == null) throw Exception('Shop profile not found');

    final branches = await _loadBranches(tenantId);
    final selectedBranchId =
        await OfflineStore.loadSelectedBranchId(_currentUser.id) ??
        profile['branch_id'] as String?;

    return AccountSettingsData(
      profile: profile,
      tenant: tenant,
      branches: branches,
      selectedBranchId: selectedBranchId,
    );
  }

  Future<void> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    final profile = await _loadProfile();
    final updated =
        Map<String, dynamic>.from(profile)
          ..['full_name'] = fullName.trim()
          ..['phone'] = phone.trim();

    await OfflineStore.saveProfile(_currentUser.id, updated);

    try {
      await _client
          .from('users')
          .update({
            'full_name': updated['full_name'],
            'phone': updated['phone'],
          })
          .eq('id', _currentUser.id)
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'update_account_profile',
        payload: {
          'user_id': _currentUser.id,
          'full_name': updated['full_name'],
          'phone': updated['phone'],
        },
      );
      debugPrint('Profile settings saved offline: $e');
    }
  }

  Future<void> updateShop({
    required String shopName,
    required String businessType,
  }) async {
    final profile = await _loadProfile();
    final tenantId = profile['tenant_id'] as String?;
    if (tenantId == null) throw Exception('Shop setup not found');

    final tenant = await _loadTenant(tenantId);
    if (tenant == null) throw Exception('Shop profile not found');

    final updated =
        Map<String, dynamic>.from(tenant)
          ..['shop_name'] = shopName.trim()
          ..['business_type'] = businessType.trim();

    await OfflineStore.saveTenant(tenantId, updated);

    try {
      await _client
          .from('tenants')
          .update({
            'shop_name': updated['shop_name'],
            'business_type': updated['business_type'],
          })
          .eq('id', tenantId)
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'update_shop_profile',
        payload: {
          'tenant_id': tenantId,
          'shop_name': updated['shop_name'],
          'business_type': updated['business_type'],
        },
      );
      debugPrint('Shop settings saved offline: $e');
    }
  }

  Future<void> updateBranch({
    required BranchInputModel branch,
    required String name,
    required String address,
    required String city,
  }) async {
    final tenantId = await _tenantId();
    final branchId = branch.id;
    if (branchId == null) throw Exception('Branch not found');

    final updatedBranch = branch.copyWith(
      name: name.trim(),
      address: address.trim(),
      city: city.trim(),
    );

    final branches = await _loadBranches(tenantId);
    final updatedBranches = [
      for (final item in branches)
        if (item.id == branchId) updatedBranch else item,
    ];
    await OfflineStore.saveBranches(tenantId, updatedBranches);

    try {
      await _client
          .from('branches')
          .update({
            'name': updatedBranch.name,
            'address': updatedBranch.address,
            'city': updatedBranch.city,
          })
          .eq('id', branchId)
          .eq('tenant_id', tenantId)
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'update_branch_profile',
        payload: {
          'tenant_id': tenantId,
          'branch_id': branchId,
          'name': updatedBranch.name,
          'address': updatedBranch.address,
          'city': updatedBranch.city,
        },
      );
      debugPrint('Branch settings saved offline: $e');
    }
  }

  Future<void> selectBranch(String branchId) async {
    await OfflineStore.selectBranch(
      userId: _currentUser.id,
      branchId: branchId,
    );

    try {
      await _client
          .from('users')
          .update({'branch_id': branchId})
          .eq('id', _currentUser.id)
          .timeout(_networkTimeout);
    } catch (e) {
      OfflineErrorClassifier.rethrowIfTerminal(e);
      await OfflineStore.enqueueMutation(
        userId: _currentUser.id,
        type: 'select_branch',
        payload: {'user_id': _currentUser.id, 'branch_id': branchId},
      );
      debugPrint('Selected branch saved offline: $e');
    }
  }

  Future<void> syncOfflineMutations() async {
    final userId = _currentUser.id;
    final mutations = await OfflineStore.loadMutations(userId);
    if (mutations.isEmpty) return;

    final remaining = <OfflineMutation>[];

    for (final mutation in mutations) {
      try {
        switch (mutation.type) {
          case 'update_account_profile':
            await _client
                .from('users')
                .update({
                  'full_name': mutation.payload['full_name'],
                  'phone': mutation.payload['phone'],
                })
                .eq('id', mutation.payload['user_id']);
            break;
          case 'update_shop_profile':
            await _client
                .from('tenants')
                .update({
                  'shop_name': mutation.payload['shop_name'],
                  'business_type': mutation.payload['business_type'],
                })
                .eq('id', mutation.payload['tenant_id']);
            break;
          case 'update_branch_profile':
            await _client
                .from('branches')
                .update({
                  'name': mutation.payload['name'],
                  'address': mutation.payload['address'],
                  'city': mutation.payload['city'],
                })
                .eq('id', mutation.payload['branch_id'])
                .eq('tenant_id', mutation.payload['tenant_id']);
            break;
          case 'select_branch':
            await _client
                .from('users')
                .update({'branch_id': mutation.payload['branch_id']})
                .eq('id', mutation.payload['user_id']);
            break;
          default:
            remaining.add(mutation);
        }
      } catch (e) {
        debugPrint('Account settings sync failed: $e');
        remaining.add(mutation);
      }
    }

    await OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: mutations,
      remaining: remaining,
    );
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final cached = await OfflineStore.loadProfile(_currentUser.id);
    if (cached != null) {
      unawaited(_refreshProfileCache());
      return cached;
    }

    final profile = await _client
        .from('users')
        .select('id, tenant_id, branch_id, full_name, email, phone, role')
        .eq('id', _currentUser.id)
        .maybeSingle()
        .timeout(_networkTimeout);

    if (profile == null) throw Exception('User profile not found');
    await OfflineStore.saveProfile(_currentUser.id, profile);
    return profile;
  }

  Future<void> _refreshProfileCache() async {
    try {
      final profile = await _client
          .from('users')
          .select('id, tenant_id, branch_id, full_name, email, phone, role')
          .eq('id', _currentUser.id)
          .maybeSingle()
          .timeout(_networkTimeout);
      if (profile != null) {
        final selectedBranchId = await OfflineStore.loadSelectedBranchId(
          _currentUser.id,
        );
        if (selectedBranchId != null) profile['branch_id'] = selectedBranchId;
        await OfflineStore.saveProfile(_currentUser.id, profile);
      }
    } catch (_) {}
  }

  Future<String> _tenantId() async {
    final profile = await _loadProfile();
    final tenantId = profile['tenant_id'] as String?;
    if (tenantId == null) throw Exception('Shop setup not found');
    return tenantId;
  }

  Future<Map<String, dynamic>?> _loadTenant(
    String tenantId, {
    bool preferRemote = false,
  }) async {
    final cached = await OfflineStore.loadTenant(tenantId);
    if (cached != null && !preferRemote) {
      unawaited(_refreshTenantCache(tenantId));
      return cached;
    }

    Map<String, dynamic>? tenant;
    try {
      tenant = await _client
          .from('tenants')
          .select(
            'id, shop_name, business_type, branch_count, plan, status, setup_complete',
          )
          .eq('id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);
    } catch (error) {
      OfflineErrorClassifier.rethrowIfTerminal(error);
      if (cached != null) return cached;
      rethrow;
    }

    if (tenant != null) await OfflineStore.saveTenant(tenantId, tenant);
    return tenant ?? cached;
  }

  Future<void> _refreshTenantCache(String tenantId) async {
    try {
      final tenant = await _client
          .from('tenants')
          .select(
            'id, shop_name, business_type, branch_count, plan, status, setup_complete',
          )
          .eq('id', tenantId)
          .maybeSingle()
          .timeout(_networkTimeout);
      if (tenant != null) await OfflineStore.saveTenant(tenantId, tenant);
    } catch (_) {}
  }

  Future<List<BranchInputModel>> _loadBranches(String tenantId) async {
    final cached = await OfflineStore.loadBranches(tenantId);
    if (cached.isNotEmpty) {
      unawaited(_refreshBranchesCache(tenantId));
      return cached;
    }

    final rows = await _client
        .from('branches')
        .select('id, name, address, city')
        .eq('tenant_id', tenantId)
        .order('id')
        .timeout(_networkTimeout);

    final branches =
        (rows as List)
            .map((row) => BranchInputModel.fromMap(row as Map<String, dynamic>))
            .toList();
    await OfflineStore.saveBranches(tenantId, branches);
    return branches;
  }

  Future<void> _refreshBranchesCache(String tenantId) async {
    try {
      final rows = await _client
          .from('branches')
          .select('id, name, address, city')
          .eq('tenant_id', tenantId)
          .order('id')
          .timeout(_networkTimeout);
      final branches =
          (rows as List)
              .map(
                (row) => BranchInputModel.fromMap(row as Map<String, dynamic>),
              )
              .toList();
      await OfflineStore.saveBranches(tenantId, branches);
    } catch (_) {}
  }
}
