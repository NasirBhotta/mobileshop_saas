import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mobileshop_saas/core/tenant_access/tenant_access_provider.dart';
import 'package:mobileshop_saas/features/onboarding/data/models/shop_setup_model.dart';
import 'package:mobileshop_saas/features/onboarding/data/repositories/setup_flow_repository.dart';
import 'package:mobileshop_saas/features/settings/data/repositories/account_settings_repository.dart';

final accountSettingsRepositoryProvider = Provider<AccountSettingsRepository>((
  ref,
) {
  return AccountSettingsRepository();
});

final accountSettingsProvider = FutureProvider.autoDispose<AccountSettingsData>(
  (ref) {
    ref.watch(tenantPlanRevisionProvider);
    return ref
        .read(accountSettingsRepositoryProvider)
        .loadSettings(refreshTenant: true);
  },
);

final accountSettingsControllerProvider =
    StateNotifierProvider<AccountSettingsController, AsyncValue<void>>((ref) {
      return AccountSettingsController(ref);
    });

class AccountSettingsController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  AccountSettingsController(this._ref) : super(const AsyncData(null));

  Future<bool> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    return _run(() {
      return _ref
          .read(accountSettingsRepositoryProvider)
          .updateProfile(fullName: fullName, phone: phone);
    });
  }

  Future<bool> updateShop({
    required String shopName,
    required String businessType,
  }) async {
    return _run(() {
      return _ref
          .read(accountSettingsRepositoryProvider)
          .updateShop(shopName: shopName, businessType: businessType);
    });
  }

  Future<bool> updateBranch({
    required BranchInputModel branch,
    required String name,
    required String address,
    required String city,
  }) async {
    return _run(() {
      return _ref
          .read(accountSettingsRepositoryProvider)
          .updateBranch(
            branch: branch,
            name: name,
            address: address,
            city: city,
          );
    });
  }

  Future<bool> selectBranch(String branchId) async {
    return _run(() {
      return _ref
          .read(accountSettingsRepositoryProvider)
          .selectBranch(branchId);
    });
  }

  Future<bool> sync() async {
    return _run(() {
      return _ref
          .read(accountSettingsRepositoryProvider)
          .syncOfflineMutations();
    });
  }

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();

    try {
      await action();
      state = const AsyncData(null);
      _ref.invalidate(accountSettingsProvider);
      _ref.invalidate(setupFlowStatusProvider);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
