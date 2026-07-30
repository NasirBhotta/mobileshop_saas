import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/data/repositories/setup_flow_repository.dart';
import 'branch_permission_shadow_evaluator.dart';
import 'permission_provider.dart';
import 'supabase_branch_permission_data_source.dart';

final branchPermissionDataSourceProvider = Provider<BranchPermissionDataSource>(
  (ref) => SupabaseBranchPermissionDataSource(),
);

final branchPermissionShadowEvaluatorProvider = Provider<
  BranchPermissionShadowEvaluator
>((ref) {
  // Recreate the snapshot cache whenever realtime/safety refresh invalidates
  // legacy permissions, so branch grants and revocations stay aligned.
  ref.watch(permissionRevisionProvider);
  return BranchPermissionShadowEvaluator(
    dataSource: ref.watch(branchPermissionDataSourceProvider),
  );
});

final branchPermissionShadowProvider =
    FutureProvider.family<BranchPermissionShadowResult?, String>((
      ref,
      key,
    ) async {
      final legacy = await ref.watch(permissionAccessProvider(key).future);
      if (legacy.userId == null || legacy.tenantId == null) return null;

      try {
        final branchId = await ref.watch(selectedBranchIdProvider.future);
        return await ref
            .watch(branchPermissionShadowEvaluatorProvider)
            .compare(
              userId: legacy.userId!,
              tenantId: legacy.tenantId!,
              branchId: branchId,
              permissionKey: key,
              legacyAllowed: legacy.isAllowed,
            );
      } catch (error) {
        debugPrint('[branch-permission-shadow] unavailable: $error');
        return null;
      }
    });

final branchAwarePermissionProvider = FutureProvider.family<bool, String>((
  ref,
  key,
) async {
  final legacy = await ref.watch(permissionAccessProvider(key).future);
  if (legacy.userId == null || legacy.tenantId == null) {
    return legacy.isAllowed;
  }

  try {
    final branchId = await ref.watch(selectedBranchIdProvider.future);
    final comparison = await ref
        .watch(branchPermissionShadowEvaluatorProvider)
        .compare(
          userId: legacy.userId!,
          tenantId: legacy.tenantId!,
          branchId: branchId,
          permissionKey: key,
          legacyAllowed: legacy.isAllowed,
        );
    return comparison.branchAllowed;
  } catch (error) {
    debugPrint(
      '[branch-permission] $key unavailable; using legacy access: $error',
    );
    return legacy.isAllowed;
  }
});
