import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/authorization/persistent_permission_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('permission snapshot survives an in-memory evaluator reset', () async {
    const assignment = PermissionRoleAssignment(
      roleId: 'owner-role',
      isActive: true,
      deletedAt: null,
      revokedAt: null,
      permissionKeys: {'user.role.manage', 'inventory.product.view'},
    );

    await PersistentPermissionCache.save(
      userId: 'user-1',
      tenantId: 'tenant-1',
      assignments: const [assignment],
    );
    final restored = await PersistentPermissionCache.load(
      userId: 'user-1',
      tenantId: 'tenant-1',
    );

    expect(restored, hasLength(1));
    expect(restored!.single.isEffective, isTrue);
    expect(restored.single.permissionKeys, contains('user.role.manage'));
  });

  test('permission snapshots remain isolated by tenant and user', () async {
    await PersistentPermissionCache.save(
      userId: 'user-1',
      tenantId: 'tenant-1',
      assignments: const [],
    );

    expect(
      await PersistentPermissionCache.load(
        userId: 'user-1',
        tenantId: 'tenant-2',
      ),
      isNull,
    );
    expect(
      await PersistentPermissionCache.load(
        userId: 'user-2',
        tenantId: 'tenant-1',
      ),
      isNull,
    );
  });
}
