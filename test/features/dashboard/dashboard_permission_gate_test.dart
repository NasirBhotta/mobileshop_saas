import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/authorization/permission_provider.dart';
import 'package:mobileshop_saas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:mobileshop_saas/features/settings/presentation/providers/account_settings_provider.dart';
import 'package:mobileshop_saas/features/settings/presentation/widgets/account_menu_button.dart';
import 'dart:io';

void main() {
  test('dashboard and navigation use branch-aware permission access', () {
    final dashboard =
        File(
          'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
        ).readAsStringSync();
    final desktopNav =
        File('lib/shared/widgets/desktop_nav.dart').readAsStringSync();
    final mobileNav =
        File('lib/shared/widgets/mobile_nav.dart').readAsStringSync();

    for (final source in [dashboard, desktopNav, mobileNav]) {
      expect(
        source,
        contains("branchAwarePermissionProvider('dashboard.overview.view')"),
      );
    }
  });

  test('branch permission tables participate in realtime refresh', () {
    final provider =
        File(
          'lib/core/authorization/permission_provider.dart',
        ).readAsStringSync();
    final migration =
        File(
          'supabase/migrations/20260726000400_enable_branch_permission_realtime.sql',
        ).readAsStringSync();

    for (final table in const [
      'user_branch_role_assignments',
      'user_branch_permission_overrides',
    ]) {
      expect(provider, contains("'$table'"));
      expect(migration, contains("'$table'"));
      expect(
        migration,
        contains('alter table public.$table replica identity full'),
      );
    }
  });

  testWidgets('dashboard stays visible as locked without view permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionDataSourceProvider.overrideWithValue(
            const _DashboardPermissionDataSource(permissionKeys: {}),
          ),
          accountSettingsProvider.overrideWith(
            (ref) => throw Exception('Account settings unavailable in test'),
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
    expect(find.byType(AccountMenuButton), findsOneWidget);
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
