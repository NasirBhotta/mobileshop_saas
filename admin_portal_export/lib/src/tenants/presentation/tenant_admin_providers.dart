import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tenant_admin_repository.dart';
import '../domain/platform_tenant.dart';

final tenantAdminRepositoryProvider = Provider<TenantAdminRepository>((ref) {
  return TenantAdminRepository();
});

final tenantSummaryProvider = FutureProvider<TenantSummary>((ref) {
  return ref.watch(tenantAdminRepositoryProvider).loadSummary();
});

class TenantFilters {
  final String search;
  final String? status;
  final String? plan;

  const TenantFilters({this.search = '', this.status, this.plan});

  TenantFilters copyWith({
    String? search,
    String? status,
    String? plan,
    bool clearStatus = false,
    bool clearPlan = false,
  }) {
    return TenantFilters(
      search: search ?? this.search,
      status: clearStatus ? null : status ?? this.status,
      plan: clearPlan ? null : plan ?? this.plan,
    );
  }
}

final tenantFiltersProvider =
    NotifierProvider<TenantFiltersNotifier, TenantFilters>(
      TenantFiltersNotifier.new,
    );

class TenantFiltersNotifier extends Notifier<TenantFilters> {
  @override
  TenantFilters build() => const TenantFilters();

  void update(TenantFilters filters) => state = filters;
}

final tenantListProvider = FutureProvider<List<PlatformTenant>>((ref) {
  final filters = ref.watch(tenantFiltersProvider);
  return ref
      .watch(tenantAdminRepositoryProvider)
      .listTenants(
        search: filters.search,
        status: filters.status,
        plan: filters.plan,
      );
});

final tenantDetailProvider = FutureProvider.family<PlatformTenant, String>((
  ref,
  id,
) {
  return ref.watch(tenantAdminRepositoryProvider).getTenant(id);
});

final tenantStatusControllerProvider =
    AsyncNotifierProvider<TenantStatusController, void>(
      TenantStatusController.new,
    );

class TenantStatusController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> change({
    required String tenantId,
    required String status,
    String? reason,
  }) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(tenantAdminRepositoryProvider)
          .setStatus(tenantId: tenantId, status: status, reason: reason);
      ref.invalidate(tenantSummaryProvider);
      ref.invalidate(tenantListProvider);
      ref.invalidate(tenantDetailProvider(tenantId));
      state = const AsyncData(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}
