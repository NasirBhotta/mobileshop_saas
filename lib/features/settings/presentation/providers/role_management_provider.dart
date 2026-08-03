import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/authorization/permission_provider.dart';
import '../../data/models/role_management_models.dart';
import '../../data/repositories/role_management_repository.dart';

final roleManagementRepositoryProvider = Provider<RoleManagementRepository>((
  ref,
) {
  return RoleManagementRepository(
    permissions: ref.watch(permissionEvaluatorProvider),
  );
});

final roleManagementAccessProvider = FutureProvider.autoDispose((ref) {
  return ref
      .watch(permissionEvaluatorProvider)
      .can(RoleManagementPermissions.manage);
});

final roleManagementProvider = FutureProvider.autoDispose<RoleManagementData>((
  ref,
) {
  return ref.read(roleManagementRepositoryProvider).load();
});

final roleManagementControllerProvider =
    StateNotifierProvider<RoleManagementController, AsyncValue<void>>((ref) {
      return RoleManagementController(ref);
    });

class RoleManagementController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  RoleManagementController(this._ref) : super(const AsyncData(null));

  Future<bool> run(
    Future<void> Function(RoleManagementRepository) action,
  ) async {
    state = const AsyncLoading();
    try {
      await action(_ref.read(roleManagementRepositoryProvider));
      state = const AsyncData(null);
      _ref.read(permissionRevisionProvider.notifier).refresh();
      _ref.invalidate(roleManagementProvider);
      _ref.invalidate(roleManagementAccessProvider);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}
