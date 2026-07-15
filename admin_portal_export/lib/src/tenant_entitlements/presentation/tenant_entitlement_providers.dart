import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tenants/presentation/tenant_admin_providers.dart';
import '../data/tenant_entitlement_repository.dart';
import '../domain/tenant_entitlement.dart';

final tenantEntitlementRepositoryProvider =
    Provider<TenantEntitlementRepository>((ref) {
      return TenantEntitlementRepository();
    });

final tenantSubscriptionProvider =
    FutureProvider.family<TenantSubscriptionInfo?, String>((ref, tenantId) {
      return ref
          .watch(tenantEntitlementRepositoryProvider)
          .getSubscription(tenantId);
    });

final tenantEffectiveFeaturesProvider = FutureProvider.family<
  List<TenantFeatureEntitlement>,
  String
>((ref, tenantId) {
  return ref.watch(tenantEntitlementRepositoryProvider).getFeatures(tenantId);
});

final tenantEffectiveLimitsProvider =
    FutureProvider.family<List<TenantLimitEntitlement>, String>((
      ref,
      tenantId,
    ) {
      return ref.watch(tenantEntitlementRepositoryProvider).getLimits(tenantId);
    });

final tenantEntitlementMutationProvider =
    AsyncNotifierProvider<TenantEntitlementMutationController, void>(
      TenantEntitlementMutationController.new,
    );

class TenantEntitlementMutationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> run(
    String tenantId,
    Future<void> Function(TenantEntitlementRepository repository) operation,
  ) async {
    state = const AsyncLoading();
    try {
      await operation(ref.read(tenantEntitlementRepositoryProvider));
      ref.invalidate(tenantSubscriptionProvider(tenantId));
      ref.invalidate(tenantEffectiveFeaturesProvider(tenantId));
      ref.invalidate(tenantEffectiveLimitsProvider(tenantId));
      ref.invalidate(tenantDetailProvider(tenantId));
      ref.invalidate(tenantListProvider);
      ref.invalidate(tenantSummaryProvider);
      state = const AsyncData(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}
