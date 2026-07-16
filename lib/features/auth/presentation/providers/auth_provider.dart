import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/authorization/permission_provider.dart';
import '../../../../core/entitlements/entitlement_provider.dart';
import '../../../../core/tenant_access/tenant_access_provider.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../onboarding/data/repositories/setup_flow_repository.dart';
import '../../../onboarding/presentation/providers/shop_setup_provider.dart';
import '../../../pos/presentation/providers/pos_provider.dart';
import '../../../repairs/presentation/providers/repair_provider.dart';
import '../../data/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
      return AuthController(ref.watch(authRepositoryProvider), ref);
    });

final authListenerProvider = StreamProvider<void>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  String? activeUserId = repo.currentUser?.id;

  await for (final authState in repo.authStateChanges) {
    final nextUserId = authState.session?.user.id;
    final userChanged = nextUserId != activeUserId;
    if (authState.event == AuthChangeEvent.signedOut || userChanged) {
      _invalidateAuthScopedProviders(ref);
    }
    activeUserId = nextUserId;

    if (authState.event == AuthChangeEvent.signedIn) {
      final user = authState.session?.user;
      if (user == null) continue;

      await repo.ensureUserProfile(user: user);
      ref.invalidate(setupFlowStatusProvider);
      ref.invalidate(selectedBranchIdProvider);
    }
  }
});

void _invalidateAuthScopedProviders(Ref ref) {
  ref.read(permissionEvaluatorProvider).invalidateAll();
  ref.read(entitlementEvaluatorProvider).invalidateAll();
  ref.invalidate(tenantAccessProvider);
  ref.invalidate(setupFlowStatusProvider);
  ref.invalidate(selectedBranchIdProvider);
  ref.invalidate(shopSetupDataProvider);
  ref.invalidate(setupStepProvider);
  ref.invalidate(setupProgressProvider);

  ref.invalidate(dashboardStatsProvider);
  ref.invalidate(tenantSettingsProvider);
  ref.invalidate(adjustmentsProvider);
  ref.invalidate(allProductsProvider);
  ref.invalidate(productsProvider);
  ref.invalidate(categoriesProvider);
  ref.invalidate(searchQueryProvider);
  ref.invalidate(selectedCategoryProvider);

  ref.invalidate(cartProvider);
  ref.invalidate(heldCartsProvider);
  ref.invalidate(salesHistoryProvider);
  ref.invalidate(allSalesProvider);
  ref.invalidate(receiptFooterProvider);
  ref.invalidate(customerSearchQueryProvider);
  ref.invalidate(customerListQueryProvider);
  ref.invalidate(customersProvider);
  ref.invalidate(allCustomersProvider);
  ref.invalidate(returnDraftProvider);
  ref.invalidate(pendingReturnsProvider);
  ref.invalidate(approvedReturnsProvider);
  ref.invalidate(allApprovedReturnsProvider);
  ref.invalidate(allCustomerSettlementsProvider);

  ref.invalidate(selectedRepairStatusFilterProvider);
  ref.invalidate(repairTicketsProvider);
  ref.invalidate(allRepairTicketsProvider);
}

class AuthController extends StateNotifier<AsyncValue<void>> {
  final AuthRepository _repository;
  final Ref _ref;

  AuthController(this._repository, this._ref) : super(const AsyncData(null));

  void clearStatus() {
    state = const AsyncData(null);
  }

  Future<bool> login({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      _invalidateAuthScopedProviders(_ref);
      await _repository.signInWithPassword(email: email, password: password);
      _invalidateAuthScopedProviders(_ref);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> signup({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    state = const AsyncLoading();
    try {
      _invalidateAuthScopedProviders(_ref);
      await _repository.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
      );
      _invalidateAuthScopedProviders(_ref);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> loginWithGoogle() async {
    state = const AsyncLoading();
    try {
      _invalidateAuthScopedProviders(_ref);
      await _repository.signInWithGoogle();
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> logout() async {
    state = const AsyncLoading();
    try {
      await _repository.signOut();
      _invalidateAuthScopedProviders(_ref);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> logoutLocally() async {
    state = const AsyncLoading();
    try {
      await _repository.signOutLocally();
      _invalidateAuthScopedProviders(_ref);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
