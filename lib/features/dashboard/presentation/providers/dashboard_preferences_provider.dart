import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../onboarding/data/repositories/setup_flow_repository.dart';
import '../../data/repositories/dashboard_preferences_repository.dart';

final dashboardPreferencesRepositoryProvider =
    Provider<DashboardPreferencesRepository>((ref) {
      return DashboardPreferencesRepository();
    });

final dashboardPreferencesProvider =
    FutureProvider.autoDispose<DashboardPreferences>((ref) async {
      // Recreate this user-scoped request when the authenticated user changes.
      // The repository cache is also keyed by user, tenant, and branch.
      ref.watch(authStateProvider);
      final branchId = await ref.watch(selectedBranchIdProvider.future);
      return ref.read(dashboardPreferencesRepositoryProvider).load(branchId);
    });

final dashboardPreferencesControllerProvider =
    StateNotifierProvider<DashboardPreferencesController, AsyncValue<void>>(
      (ref) => DashboardPreferencesController(ref),
    );

class DashboardPreferencesController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  DashboardPreferencesController(this._ref) : super(const AsyncData(null));

  Future<bool> save(List<String> accountIds) async {
    state = const AsyncLoading();
    try {
      final branchId = await _ref.read(selectedBranchIdProvider.future);
      await _ref
          .read(dashboardPreferencesRepositoryProvider)
          .save(branchId: branchId, accountIds: accountIds);
      state = const AsyncData(null);
      _ref.invalidate(dashboardPreferencesProvider);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}
