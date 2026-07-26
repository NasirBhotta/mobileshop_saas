import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/authorization/permission_provider.dart';
import 'package:mobileshop_saas/features/dashboard/presentation/screens/dashboard_screen.dart';

void main() {
  testWidgets('dashboard stays visible as locked without view permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionDataSourceProvider.overrideWithValue(
            const _DashboardPermissionDataSource(permissionKeys: {}),
          ),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard locked hai'), findsOneWidget);
    expect(
      find.text('Is module ke liye owner ki permission required hai.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('permission-lock-icon')), findsOneWidget);
  });
}

class _DashboardPermissionDataSource implements PermissionDataSource {
  final Set<String> permissionKeys;

  const _DashboardPermissionDataSource({required this.permissionKeys});

  @override
  String? get currentUserId => 'staff-user';

  @override
  Future<String?> loadTenantId(String userId) async => 'tenant-1';

  @override
  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  }) async {
    return [
      PermissionRoleAssignment(
        roleId: 'custom-manager-role',
        isActive: true,
        deletedAt: null,
        revokedAt: null,
        permissionKeys: permissionKeys,
      ),
    ];
  }
}
