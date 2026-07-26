import 'package:flutter/foundation.dart';

@immutable
class BranchPermissionSnapshot {
  final bool isOwner;
  final bool hasBranchConfiguration;
  final bool hasActiveBranchRole;
  final Set<String> rolePermissionKeys;
  final Map<String, bool> permissionOverrides;

  const BranchPermissionSnapshot({
    required this.isOwner,
    required this.hasBranchConfiguration,
    required this.hasActiveBranchRole,
    required this.rolePermissionKeys,
    required this.permissionOverrides,
  });
}

abstract interface class BranchPermissionDataSource {
  Future<BranchPermissionSnapshot> loadSnapshot({
    required String userId,
    required String tenantId,
    required String branchId,
  });
}

enum BranchPermissionShadowMode { owner, legacyFallback, branchScoped }

@immutable
class BranchPermissionShadowResult {
  final String permissionKey;
  final String branchId;
  final bool legacyAllowed;
  final bool branchAllowed;
  final BranchPermissionShadowMode mode;

  const BranchPermissionShadowResult({
    required this.permissionKey,
    required this.branchId,
    required this.legacyAllowed,
    required this.branchAllowed,
    required this.mode,
  });

  bool get differs => legacyAllowed != branchAllowed;

  // Shadow mode must never change the application's authorization decision.
  bool get effectiveAllowed => legacyAllowed;
}

class BranchPermissionShadowEvaluator {
  final BranchPermissionDataSource _dataSource;
  final void Function(String message) _logger;

  BranchPermissionShadowEvaluator({
    required BranchPermissionDataSource dataSource,
    void Function(String message)? logger,
  }) : _dataSource = dataSource,
       _logger = logger ?? debugPrint;

  Future<BranchPermissionShadowResult> compare({
    required String userId,
    required String tenantId,
    required String branchId,
    required String permissionKey,
    required bool legacyAllowed,
  }) async {
    final snapshot = await _dataSource.loadSnapshot(
      userId: userId,
      tenantId: tenantId,
      branchId: branchId,
    );

    late final bool branchAllowed;
    late final BranchPermissionShadowMode mode;
    if (snapshot.isOwner) {
      branchAllowed = true;
      mode = BranchPermissionShadowMode.owner;
    } else if (!snapshot.hasBranchConfiguration) {
      branchAllowed = legacyAllowed;
      mode = BranchPermissionShadowMode.legacyFallback;
    } else {
      final override = snapshot.permissionOverrides[permissionKey];
      branchAllowed =
          snapshot.hasActiveBranchRole &&
          (override ?? snapshot.rolePermissionKeys.contains(permissionKey));
      mode = BranchPermissionShadowMode.branchScoped;
    }

    final result = BranchPermissionShadowResult(
      permissionKey: permissionKey,
      branchId: branchId,
      legacyAllowed: legacyAllowed,
      branchAllowed: branchAllowed,
      mode: mode,
    );
    if (result.differs) {
      _logger(
        '[branch-permission-shadow] user=$userId branch=$branchId '
        'permission=$permissionKey legacy=$legacyAllowed '
        'branch=$branchAllowed mode=${mode.name}',
      );
    }
    return result;
  }
}
