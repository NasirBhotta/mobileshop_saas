import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/package_admin_repository.dart';
import '../domain/platform_plan.dart';

final packageAdminRepositoryProvider = Provider<PackageAdminRepository>(
  (ref) => PackageAdminRepository(),
);
final plansProvider = FutureProvider<List<PlatformPlan>>(
  (ref) => ref.watch(packageAdminRepositoryProvider).listPlans(),
);
final planProvider = FutureProvider.family<PlatformPlan, String>(
  (ref, id) => ref.watch(packageAdminRepositoryProvider).getPlan(id),
);
final planFeaturesProvider = FutureProvider.family<List<PlanFeature>, String>(
  (ref, id) => ref.watch(packageAdminRepositoryProvider).listFeatures(id),
);
final planLimitsProvider = FutureProvider.family<List<PlanLimit>, String>(
  (ref, id) => ref.watch(packageAdminRepositoryProvider).listLimits(id),
);

final packageMutationProvider =
    AsyncNotifierProvider<PackageMutationController, void>(
      PackageMutationController.new,
    );

class PackageMutationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<T?> run<T>(
    Future<T> Function(PackageAdminRepository repository) operation, {
    String? planId,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await operation(ref.read(packageAdminRepositoryProvider));
      ref.invalidate(plansProvider);
      if (planId != null) {
        ref.invalidate(planProvider(planId));
        ref.invalidate(planFeaturesProvider(planId));
        ref.invalidate(planLimitsProvider(planId));
      }
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }
}
