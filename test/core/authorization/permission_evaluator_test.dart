import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';

void main() {
  group('PermissionEvaluator', () {
    test('owner, manager, and cashier permissions load correctly', () async {
      final dataSource = _FakePermissionDataSource();
      final evaluator = PermissionEvaluator(dataSource: dataSource);

      dataSource.assignments = [
        _assignment('owner', {'owner.only', 'shared'}),
      ];
      expect((await evaluator.can('owner.only')).isAllowed, isTrue);

      dataSource.userId = 'manager-user';
      dataSource.assignments = [
        _assignment('manager', {'manager.approve', 'shared'}),
      ];
      expect((await evaluator.can('manager.approve')).isAllowed, isTrue);
      expect((await evaluator.can('owner.only')).isAllowed, isFalse);

      dataSource.userId = 'cashier-user';
      dataSource.assignments = [
        _assignment('cashier', {'shared'}),
      ];
      expect((await evaluator.can('shared')).isAllowed, isTrue);
      expect((await evaluator.can('manager.approve')).isAllowed, isFalse);
    });

    test('inactive, deleted, and revoked roles are ignored', () async {
      final dataSource = _FakePermissionDataSource(
        assignments: [
          _assignment('inactive', {'shared'}, isActive: false),
          _assignment('deleted', {'shared'}, deletedAt: DateTime(2026)),
          _assignment('revoked', {'shared'}, revokedAt: DateTime(2026)),
        ],
      );
      final result = await PermissionEvaluator(
        dataSource: dataSource,
      ).can('shared');

      expect(result.isAllowed, isFalse);
      expect(
        result.denialReason,
        PermissionDenialReason.noActiveRoleAssignment,
      );
    });

    test('missing assignment returns a typed safe denial', () async {
      final result = await PermissionEvaluator(
        dataSource: _FakePermissionDataSource(assignments: const []),
      ).can('inventory.product.view');

      expect(result.isAllowed, isFalse);
      expect(
        result.denialReason,
        PermissionDenialReason.noActiveRoleAssignment,
      );
    });

    test(
      'cache invalidates for assignment, tenant, login, and logout',
      () async {
        final dataSource = _FakePermissionDataSource(
          assignments: [
            _assignment('cashier', {'shared'}),
          ],
        );
        final evaluator = PermissionEvaluator(dataSource: dataSource);

        expect((await evaluator.can('shared')).fromCache, isFalse);
        expect((await evaluator.can('shared')).fromCache, isTrue);
        expect(dataSource.loadCount, 1);

        dataSource.assignments = [
          _assignment('cashier', {'new.permission'}),
        ];
        evaluator.invalidateRoleAssignments(
          userId: dataSource.userId!,
          tenantId: dataSource.tenantId!,
        );
        expect((await evaluator.can('new.permission')).isAllowed, isTrue);
        expect(dataSource.loadCount, 2);

        dataSource.tenantId = 'tenant-2';
        expect((await evaluator.can('new.permission')).fromCache, isFalse);
        expect(dataSource.loadCount, 3);

        dataSource.userId = null;
        evaluator.invalidateAll();
        expect(
          (await evaluator.can('new.permission')).denialReason,
          PermissionDenialReason.unauthenticated,
        );

        dataSource.userId = 'new-login-user';
        expect((await evaluator.can('new.permission')).fromCache, isFalse);
        expect(dataSource.loadCount, 4);
      },
    );

    test(
      'shadow comparison logs mismatch without changing legacy decision',
      () async {
        final messages = <String>[];
        final evaluator = PermissionEvaluator(
          dataSource: _FakePermissionDataSource(
            assignments: [
              _assignment('cashier', {'shared'}),
            ],
          ),
          shadowLogger: messages.add,
        );

        final diagnostic = await evaluator.compareWithLegacy(
          permissionKey: 'owner.only',
          legacyAllowed: true,
        );

        expect(diagnostic.isAllowed, isFalse);
        expect(messages, hasLength(1));
      },
    );
  });
}

PermissionRoleAssignment _assignment(
  String roleId,
  Set<String> permissions, {
  bool isActive = true,
  DateTime? deletedAt,
  DateTime? revokedAt,
}) {
  return PermissionRoleAssignment(
    roleId: roleId,
    isActive: isActive,
    deletedAt: deletedAt,
    revokedAt: revokedAt,
    permissionKeys: permissions,
  );
}

class _FakePermissionDataSource implements PermissionDataSource {
  String? userId;
  String? tenantId;
  List<PermissionRoleAssignment> assignments;
  int loadCount = 0;

  _FakePermissionDataSource({this.assignments = const []})
    : userId = 'owner-user',
      tenantId = 'tenant-1';

  @override
  String? get currentUserId => userId;

  @override
  Future<String?> loadTenantId(String userId) async => tenantId;

  @override
  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  }) async {
    loadCount++;
    return assignments;
  }
}
