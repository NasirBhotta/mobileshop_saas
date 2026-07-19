import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/shop_setup_model.dart';
import '../../data/repositories/setup_flow_repository.dart';

final shopSetupDataProvider =
    StateNotifierProvider<ShopSetupNotifier, ShopSetupModel>((ref) {
      return ShopSetupNotifier();
    });

class ShopSetupNotifier extends StateNotifier<ShopSetupModel> {
  ShopSetupNotifier() : super(const ShopSetupModel());

  void updateBasics({
    required String shopName,
    required String city,
    required String address,
  }) {
    state = state.copyWith(
      shopName: shopName,
      city: city,
      address: address,
      branches: _syncBranches(
        branchCount: state.branchCount,
        city: city,
        address: address,
      ),
    );
  }

  void updateBusinessDetails({
    required String businessType,
    required int branchCount,
  }) {
    state = state.copyWith(
      businessType: businessType,
      branchCount: branchCount < 1 ? 1 : branchCount,
      branches: _syncBranches(
        branchCount: branchCount,
        city: state.city,
        address: state.address,
      ),
    );
  }

  void updateFromTenant({
    required String shopName,
    required String businessType,
    required int branchCount,
  }) {
    state = state.copyWith(
      shopName: shopName,
      businessType: businessType,
      branchCount: branchCount < 1 ? 1 : branchCount,
      branches: _syncBranches(
        branchCount: branchCount,
        city: state.city,
        address: state.address,
      ),
    );
  }

  List<BranchInputModel> _syncBranches({
    required int branchCount,
    required String city,
    required String address,
  }) {
    final count = branchCount < 1 ? 1 : branchCount;
    final branches = List<BranchInputModel>.from(state.branches);

    while (branches.length < count) {
      branches.add(BranchInputModel(name: 'Branch ${branches.length + 1}'));
    }

    if (branches.length > count) {
      branches.removeRange(count, branches.length);
    }

    branches[0] = branches[0].copyWith(
      name: branches[0].name.isEmpty ? 'Main Branch' : branches[0].name,
      city: branches[0].city.isEmpty ? city : branches[0].city,
      address: branches[0].address.isEmpty ? address : branches[0].address,
    );

    return branches;
  }
}

final setupStepProvider = StateProvider<int>((ref) => 0);

class SetupProgressState {
  final bool isLoaded;
  final String? tenantId;
  final int branchCount;
  final int completedBranches;

  const SetupProgressState({
    this.isLoaded = false,
    this.tenantId,
    this.branchCount = 1,
    this.completedBranches = 0,
  });

  bool get isComplete => completedBranches >= branchCount;
  int get nextBranchNumber => isComplete ? branchCount : completedBranches + 1;

  SetupProgressState copyWith({
    bool? isLoaded,
    String? tenantId,
    int? branchCount,
    int? completedBranches,
  }) {
    return SetupProgressState(
      isLoaded: isLoaded ?? this.isLoaded,
      tenantId: tenantId ?? this.tenantId,
      branchCount: branchCount ?? this.branchCount,
      completedBranches: completedBranches ?? this.completedBranches,
    );
  }
}

final setupProgressProvider = StateProvider<SetupProgressState>((ref) {
  return const SetupProgressState();
});

final setupSubmitControllerProvider =
    StateNotifierProvider<SetupSubmitController, AsyncValue<void>>((ref) {
      return SetupSubmitController(ref);
    });

class SetupSubmitController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  late final SetupFlowRepository _repository = _ref.read(
    setupFlowRepositoryProvider,
  );

  SetupSubmitController(this._ref) : super(const AsyncData(null));

  void clearStatus() {
    state = const AsyncData(null);
  }

  void setValidationError(String message) {
    state = AsyncError(Exception(message), StackTrace.current);
  }

  Future<void> loadResumeState() async {
    state = const AsyncLoading();
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final status = await _repository.loadStatus(user.id);
      final tenant = status.tenant;

      if (tenant != null && status.target == SetupRouteTarget.setup) {
        final branchCount = ((tenant['branch_count'] as num?) ?? 1).toInt();

        _ref
            .read(shopSetupDataProvider.notifier)
            .updateFromTenant(
              shopName: (tenant['shop_name'] as String?) ?? '',
              businessType: (tenant['business_type'] as String?) ?? '',
              branchCount: branchCount,
            );

        _ref.read(setupProgressProvider.notifier).state = SetupProgressState(
          isLoaded: true,
          tenantId: tenant['id'] as String?,
          branchCount: branchCount,
          completedBranches: status.branches.length,
        );
        _ref.read(setupStepProvider.notifier).state = 3;
      } else {
        _ref
            .read(setupProgressProvider.notifier)
            .state = const SetupProgressState(isLoaded: true);
        _ref.read(setupStepProvider.notifier).state = 0;
      }

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<bool> submitBusinessSetup() async {
    state = const AsyncLoading();
    try {
      final data = _ref.read(shopSetupDataProvider);
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) throw Exception('User not logged in');
      if (data.shopName.trim().isEmpty) throw Exception('Shop name required');
      if (data.businessType.isEmpty) throw Exception('Business type required');

      final tenantId = await _repository.ensureTenant(
        user: user,
        shopName: data.shopName.trim(),
        businessType: data.businessType,
        branchCount: data.branchCount,
      );
      final completedBranches = await _repository.countBranches(tenantId);

      _ref.invalidate(setupFlowStatusProvider);
      _ref.invalidate(selectedBranchIdProvider);
      _ref.read(setupProgressProvider.notifier).state = SetupProgressState(
        isLoaded: true,
        tenantId: tenantId,
        branchCount: data.branchCount,
        completedBranches: completedBranches,
      );
      _ref.read(setupStepProvider.notifier).state = 3;

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<SetupRouteTarget?> submitCurrentBranch(BranchInputModel branch) async {
    state = const AsyncLoading();
    try {
      final progress = _ref.read(setupProgressProvider);
      final user = Supabase.instance.client.auth.currentUser;
      final tenantId = progress.tenantId;

      if (user == null) throw Exception('User not logged in');
      if (tenantId == null) throw Exception('Tenant setup required');
      if (branch.city.trim().isEmpty) throw Exception('City required');
      if (branch.address.trim().isEmpty) throw Exception('Address required');

      final completedBranches = await _repository.createNextBranch(
        tenantId: tenantId,
        branchCount: progress.branchCount,
        branch: branch,
      );

      _ref.read(setupProgressProvider.notifier).state = progress.copyWith(
        completedBranches: completedBranches,
      );

      if (completedBranches >= progress.branchCount) {
        final target = await completeSetupIfReady();
        return target;
      }

      state = const AsyncData(null);
      return SetupRouteTarget.setup;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<SetupRouteTarget?> completeSetupIfReady() async {
    state = const AsyncLoading();
    try {
      final progress = _ref.read(setupProgressProvider);
      final user = Supabase.instance.client.auth.currentUser;
      final tenantId = progress.tenantId;

      if (user == null) throw Exception('User not logged in');
      if (tenantId == null || !progress.isComplete) {
        state = const AsyncData(null);
        return null;
      }

      await _repository.markSetupComplete(tenantId);
      if (progress.branchCount == 1) {
        final branches = await _repository.loadBranches(tenantId);
        final branchId = branches.length == 1 ? branches.first.id : null;
        if (branchId != null) {
          await _repository.selectBranch(userId: user.id, branchId: branchId);
        }
      }
      final status = await _repository.loadStatus(user.id);
      _ref.invalidate(setupFlowStatusProvider);
      _ref.invalidate(selectedBranchIdProvider);

      state = const AsyncData(null);

      if (status.target == SetupRouteTarget.setup) {
        return progress.branchCount > 1
            ? SetupRouteTarget.branchSelection
            : SetupRouteTarget.dashboard;
      }

      return status.target;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}
