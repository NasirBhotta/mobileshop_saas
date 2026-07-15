import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      ref.invalidate(billingSummaryProvider(id));
      ref.invalidate(billingInvoicesProvider(id));
      ref.invalidate(billingPaymentsProvider(id));
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }
}
