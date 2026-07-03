import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/auth/presentation/screens/login_screen.dart';
import 'package:mobileshop_saas/features/auth/presentation/screens/signup_screen.dart';
import 'package:mobileshop_saas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/presentation/screens/categories_screen.dart';
import 'package:mobileshop_saas/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:mobileshop_saas/features/inventory/presentation/screens/product_form_screen.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/app_intro_screen.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/branch_selection_screen.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/shop_setup_screen.dart';
import 'package:mobileshop_saas/features/onboarding/data/repositories/setup_flow_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final profileCompleteProvider = FutureProvider<bool>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;

  final status = await ref
      .read(setupFlowRepositoryProvider)
      .loadStatus(user.id);
  return status.target != SetupRouteTarget.setup;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final location = state.uri.path;

      final prefs = await SharedPreferences.getInstance();

      final seenIntro = prefs.getBool('intro_seen') ?? false;

      if (!seenIntro) {
        return location == '/intro' ? null : '/intro';
      }

      if (location == '/intro') {
        return '/';
      }

      final session = Supabase.instance.client.auth.currentSession;
      final isAuthRoute = location == '/login' || location == '/signup';

      if (session == null) {
        return isAuthRoute ? null : '/login';
      }

      if (isAuthRoute) {
        return '/';
      }

      debugPrint("Router evaluating: ${state.uri.path}");

      final setupStatus = await ref
          .read(setupFlowRepositoryProvider)
          .loadStatus(session.user.id);

      debugPrint("Router target: ${setupStatus.target}");

      if (setupStatus.target == SetupRouteTarget.setup) {
        return location == '/setup' ? null : '/setup';
      }

      if (setupStatus.target == SetupRouteTarget.branchSelection) {
        return location == '/select-branch' ? null : '/select-branch';
      }

      if (location == '/select-branch' && setupStatus.branches.length >= 2) {
        return null;
      }

      if (location == '/' ||
          location == '/setup' ||
          location == '/select-branch') {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => null),
      GoRoute(
        path: '/intro',
        builder: (context, state) => const AppIntroScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      // Email verification screen is temporarily disabled during development.
      // Re-enable this route when email confirmation is turned back on.
      // GoRoute(
      //   path: '/verify-email',
      //   builder:
      //       (context, state) => EmailVerificationPendingScreen(
      //         email: state.uri.queryParameters['email'] ?? '',
      //       ),
      // ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const ShopSetupScreen(),
      ),
      GoRoute(
        path: '/select-branch',
        builder: (context, state) => const BranchSelectionScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),

      GoRoute(path: '/inventory', builder: (_, _) => const InventoryScreen()),
      GoRoute(
        path: '/inventory/add',
        builder: (_, _) => const ProductFormScreen(),
      ),
      GoRoute(
        path: '/inventory/edit',
        builder:
            (context, state) =>
                ProductFormScreen(product: state.extra as ProductModel?),
      ),
      GoRoute(
        path: '/inventory/categories',
        builder: (_, _) => const CategoriesScreen(), // next step mein banayenge
      ),
    ],
  );
});
