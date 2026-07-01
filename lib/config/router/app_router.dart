import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobileshop_saas/features/auth/presentation/screens/login_screen.dart';
import 'package:mobileshop_saas/features/auth/presentation/screens/signup_screen.dart';
import 'package:mobileshop_saas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/app_intro_screen.dart';
import 'package:mobileshop_saas/features/onboarding/presentation/screens/shop_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final profileCompleteProvider = FutureProvider<bool>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;

  final response =
      await Supabase.instance.client
          .from('users')
          .select('tenant_id')
          .eq('id', user.id)
          .maybeSingle();

  return response?['tenant_id'] != null;
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

      final setupDone = await _isShopSetupDone(session.user.id);

      if (!setupDone) {
        return location == '/setup' ? null : '/setup';
      }

      if (location == '/' || location == '/setup') {
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
      GoRoute(
        path: '/setup',
        builder: (context, state) => const ShopSetupScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
    ],
  );
});

Future<bool> _isShopSetupDone(String userId) async {
  final profile =
      await Supabase.instance.client
          .from('profiles')
          .select('shop_name')
          .eq('id', userId)
          .maybeSingle();

  final shopName = profile?['shop_name'];
  return shopName is String && shopName.trim().isNotEmpty;
}
