import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/domain/admin_access.dart';
import '../addons/presentation/addon_list_screen.dart';
import '../auth/presentation/access_denied_screen.dart';
import '../auth/presentation/admin_auth_providers.dart';
import '../auth/presentation/admin_login_screen.dart';
import '../dashboard/admin_dashboard_screen.dart';
import '../packages/presentation/plan_detail_screen.dart';
import '../packages/presentation/plan_list_screen.dart';
import '../platform/presentation/platform_settings_screen.dart';
import '../shell/platform_admin_shell.dart';
import '../support/presentation/audit_support_screen.dart';
import '../tenants/presentation/tenant_detail_screen.dart';
import '../tenants/presentation/tenant_list_screen.dart';
import 'admin_access_guard.dart';

final adminRouterProvider = Provider<GoRouter>((ref) {
  final access = ref.watch(adminAccessProvider);
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      if (access.isLoading) return '/loading';
      if (access.hasError) {
        return state.matchedLocation == '/access-denied'
            ? null
            : '/access-denied';
      }
      return adminRedirect(
        access: access.value ?? AdminAccess.signedOut,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder:
            (_, _) => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
      ),
      GoRoute(path: '/login', builder: (_, _) => const AdminLoginScreen()),
      GoRoute(
        path: '/access-denied',
        builder: (_, _) => const AccessDeniedScreen(),
      ),
      ShellRoute(
        builder:
            (_, state, child) =>
                PlatformAdminShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const AdminDashboardScreen()),
          GoRoute(
            path: '/tenants',
            builder: (_, _) => const TenantListScreen(),
            routes: [
              GoRoute(
                path: ':tenantId',
                builder:
                    (_, state) => TenantDetailScreen(
                      tenantId: state.pathParameters['tenantId']!,
                    ),
              ),
            ],
          ),
          GoRoute(
            path: '/plans',
            builder: (_, _) => const PlanListScreen(),
            routes: [
              GoRoute(
                path: ':planId',
                builder:
                    (_, state) => PlanDetailScreen(
                      planId: state.pathParameters['planId']!,
                    ),
              ),
            ],
          ),
          GoRoute(path: '/addons', builder: (_, _) => const AddonListScreen()),
          GoRoute(
            path: '/support',
            builder: (_, _) => const AuditSupportScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const PlatformSettingsScreen(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
