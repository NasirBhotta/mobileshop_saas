import 'package:flutter/foundation.dart';

enum PermissionDenialReason {
  unauthenticated,
  tenantUnavailable,
  noActiveRoleAssignment,
  permissionMissing,
}

@immutable
class PermissionAccessResult {
  final String permissionKey;
  final bool isAllowed;
  final PermissionDenialReason? denialReason;
  final String? userId;
  final String? tenantId;
  final bool fromCache;

  const PermissionAccessResult._({
    required this.permissionKey,
    required this.isAllowed,
    required this.denialReason,
    required this.userId,
    required this.tenantId,
    required this.fromCache,
  });

  const PermissionAccessResult.allowed({
    required String permissionKey,
    required String userId,
    required String tenantId,
    required bool fromCache,
  }) : this._(
         permissionKey: permissionKey,
         isAllowed: true,
         denialReason: null,
         userId: userId,
         tenantId: tenantId,
         fromCache: fromCache,
       );

  const PermissionAccessResult.denied({
    required String permissionKey,
    required PermissionDenialReason reason,
    String? userId,
    String? tenantId,
    bool fromCache = false,
  }) : this._(
         permissionKey: permissionKey,
         isAllowed: false,
         denialReason: reason,
         userId: userId,
         tenantId: tenantId,
         fromCache: fromCache,
       );
}

class PermissionDeniedException implements Exception {
  final String permissionKey;
  final PermissionDenialReason? reason;
  final String message;

  const PermissionDeniedException({
    required this.permissionKey,
    required this.reason,
    required this.message,
  });

  @override
  String toString() => message;
}

@immutable
class PermissionRoleAssignment {
  final String roleId;
  final bool isActive;
  final DateTime? deletedAt;
  final DateTime? revokedAt;
  final Set<String> permissionKeys;

  const PermissionRoleAssignment({
    required this.roleId,
    required this.isActive,
    required this.deletedAt,
    required this.revokedAt,
    required this.permissionKeys,
  });

  bool get isEffective => isActive && deletedAt == null && revokedAt == null;
}

abstract interface class PermissionDataSource {
  String? get currentUserId;

  Future<String?> loadTenantId(String userId);

  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  });
}

class PermissionEvaluator {
  final PermissionDataSource _dataSource;
  final void Function(String message) _shadowLogger;
  final Map<_PermissionCacheKey, _PermissionCacheEntry> _cache = {};
  final Map<_PermissionCacheKey, Future<_PermissionCacheEntry>> _inFlight = {};
  final Map<String, String> _lastTenantByUser = {};

  PermissionEvaluator({
    required PermissionDataSource dataSource,
    void Function(String message)? shadowLogger,
  }) : _dataSource = dataSource,
       _shadowLogger = shadowLogger ?? debugPrint;

  Future<PermissionAccessResult> can(String permissionKey) async {
    final userId = _dataSource.currentUserId;
    if (userId == null) {
      return PermissionAccessResult.denied(
        permissionKey: permissionKey,
        reason: PermissionDenialReason.unauthenticated,
      );
    }

    final tenantId = await _dataSource.loadTenantId(userId);
    if (tenantId == null) {
      invalidateForUser(userId);
      return PermissionAccessResult.denied(
        permissionKey: permissionKey,
        reason: PermissionDenialReason.tenantUnavailable,
        userId: userId,
      );
    }

    return canFor(
      userId: userId,
      tenantId: tenantId,
      permissionKey: permissionKey,
    );
  }

  Future<PermissionAccessResult> canFor({
    required String userId,
    required String tenantId,
    required String permissionKey,
  }) async {
    final previousTenantId = _lastTenantByUser[userId];
    if (previousTenantId != null && previousTenantId != tenantId) {
      invalidateForUser(userId);
    }
    _lastTenantByUser[userId] = tenantId;

    final cacheKey = _PermissionCacheKey(userId, tenantId);
    var fromCache = true;
    var entry = _cache[cacheKey];
    if (entry == null) {
      fromCache = false;
      var load = _inFlight[cacheKey];
      if (load == null) {
        load = _loadEntry(userId: userId, tenantId: tenantId);
        _inFlight[cacheKey] = load;
      }
      try {
        entry = await load;
        if (identical(_inFlight[cacheKey], load)) {
          _cache[cacheKey] = entry;
        }
      } finally {
        if (identical(_inFlight[cacheKey], load)) {
          _inFlight.remove(cacheKey);
        }
      }
    }

    if (!entry.hasActiveAssignment) {
      return PermissionAccessResult.denied(
        permissionKey: permissionKey,
        reason: PermissionDenialReason.noActiveRoleAssignment,
        userId: userId,
        tenantId: tenantId,
        fromCache: fromCache,
      );
    }

    if (!entry.permissionKeys.contains(permissionKey)) {
      return PermissionAccessResult.denied(
        permissionKey: permissionKey,
        reason: PermissionDenialReason.permissionMissing,
        userId: userId,
        tenantId: tenantId,
        fromCache: fromCache,
      );
    }

    return PermissionAccessResult.allowed(
      permissionKey: permissionKey,
      userId: userId,
      tenantId: tenantId,
      fromCache: fromCache,
    );
  }

  Future<void> require(String permissionKey, {required String message}) async {
    final result = await can(permissionKey);
    if (result.isAllowed) return;
    throw PermissionDeniedException(
      permissionKey: permissionKey,
      reason: result.denialReason,
      message: message,
    );
  }

  /// Shadow-only comparison. The returned database result is diagnostic and
  /// callers must continue using [legacyAllowed] for current authorization.
  Future<PermissionAccessResult> compareWithLegacy({
    required String permissionKey,
    required bool legacyAllowed,
  }) async {
    final result = await can(permissionKey);
    if (result.isAllowed != legacyAllowed) {
      _shadowLogger(
        '[permission-shadow] $permissionKey legacy=$legacyAllowed '
        'database=${result.isAllowed} reason=${result.denialReason?.name}',
      );
    }
    return result;
  }

  void invalidateRoleAssignments({
    required String userId,
    required String tenantId,
  }) {
    final key = _PermissionCacheKey(userId, tenantId);
    _cache.remove(key);
    _inFlight.remove(key);
  }

  void invalidateForUser(String userId) {
    _cache.removeWhere((key, _) => key.userId == userId);
    _inFlight.removeWhere((key, _) => key.userId == userId);
    _lastTenantByUser.remove(userId);
  }

  void invalidateAll() {
    _cache.clear();
    _inFlight.clear();
    _lastTenantByUser.clear();
  }

  Future<_PermissionCacheEntry> _loadEntry({
    required String userId,
    required String tenantId,
  }) async {
    final assignments = await _dataSource.loadRoleAssignments(
      userId: userId,
      tenantId: tenantId,
    );
    final activeAssignments = assignments.where(
      (assignment) => assignment.isEffective,
    );
    return _PermissionCacheEntry(
      hasActiveAssignment: activeAssignments.isNotEmpty,
      permissionKeys: {
        for (final assignment in activeAssignments)
          ...assignment.permissionKeys,
      },
    );
  }
}

@immutable
class _PermissionCacheKey {
  final String userId;
  final String tenantId;

  const _PermissionCacheKey(this.userId, this.tenantId);

  @override
  bool operator ==(Object other) =>
      other is _PermissionCacheKey &&
      other.userId == userId &&
      other.tenantId == tenantId;

  @override
  int get hashCode => Object.hash(userId, tenantId);
}

class _PermissionCacheEntry {
  final bool hasActiveAssignment;
  final Set<String> permissionKeys;

  const _PermissionCacheEntry({
    required this.hasActiveAssignment,
    required this.permissionKeys,
  });
}
