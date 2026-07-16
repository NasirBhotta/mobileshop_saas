import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tenant_entitlements/presentation/tenant_entitlement_providers.dart';
import '../../tenants/presentation/tenant_admin_providers.dart';
import '../data/billing_repository.dart';
import '../domain/tenant_billing.dart';

final billingRepositoryProvider = Provider((ref) => BillingRepository());
final billingSummaryProvider = FutureProvider.family<BillingSummary?, String>(
  (ref, id) => ref.watch(billingRepositoryProvider).summary(id),
);
final billingInvoicesProvider =
    FutureProvider.family<List<BillingInvoice>, String>(
      (ref, id) => ref.watch(billingRepositoryProvider).invoices(id),
    );
final billingPaymentsProvider =
    FutureProvider.family<List<BillingPayment>, String>(
      (ref, id) => ref.watch(billingRepositoryProvider).payments(id),
    );
final billingPlansProvider = FutureProvider<List<BillingPlan>>(
  (ref) => ref.watch(billingRepositoryProvider).plans(),
);
final billingMutationProvider = AsyncNotifierProvider<BillingMutation, void>(
  BillingMutation.new,
);

class BillingMutation extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}
  Future<bool> run(
    String id,
    Future<void> Function(BillingRepository) operation,
  ) async {
    state = const AsyncLoading();
    try {
      await operation(ref.read(billingRepositoryProvider));
      ref.invalidate(tenantSubscriptionProvider(id));
      ref.invalidate(tenantEffectiveFeaturesProvider(id));
      ref.invalidate(tenantEffectiveLimitsProvider(id));
      ref.invalidate(tenantDetailProvider(id));
      ref.invalidate(tenantListProvider);
      ref.invalidate(tenantSummaryProvider);
      await Future.wait([
        ref.refresh(billingSummaryProvider(id).future),
        ref.refresh(billingInvoicesProvider(id).future),
        ref.refresh(billingPaymentsProvider(id).future),
      ]);
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }
}
