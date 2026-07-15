import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/addon_repository.dart';
import '../domain/platform_addon.dart';

final addonRepositoryProvider = Provider((ref) => AddonRepository());
final addonsProvider = FutureProvider<List<PlatformAddon>>(
  (ref) => ref.watch(addonRepositoryProvider).list(),
);
final tenantAddonsProvider = FutureProvider.family<List<TenantAddon>, String>(
  (ref, id) => ref.watch(addonRepositoryProvider).tenantAddons(id),
);
final tenantUsageProvider = FutureProvider.family<List<TenantUsage>, String>(
  (ref, id) => ref.watch(addonRepositoryProvider).usage(id),
);
final addonMutationProvider = AsyncNotifierProvider<AddonMutation, void>(
  AddonMutation.new,
);

class AddonMutation extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}
  Future<bool> run(
    Future<void> Function(AddonRepository) fn, {
    String? tenantId,
  }) async {
    state = const AsyncLoading();
    try {
      await fn(ref.read(addonRepositoryProvider));
      ref.invalidate(addonsProvider);
      if (tenantId != null) {
        ref.invalidate(tenantAddonsProvider(tenantId));
        ref.invalidate(tenantUsageProvider(tenantId));
      }
      state = const AsyncData(null);
      return true;
    } catch (e, s) {
      state = AsyncError(e, s);
      return false;
    }
  }
}
