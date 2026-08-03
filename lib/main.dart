import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/auth/presentation/providers/auth_provider.dart';
import 'package:mobileshop_saas/features/mobile_services/presentation/providers/mobile_services_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/router/app_router.dart';
import 'config/supabase/supabase_config.dart';
import 'config/theme/app_theme.dart';
import 'core/authorization/permission_provider.dart';
import 'core/constants/app_colors.dart';
import 'core/constants/app_strings.dart';
import 'core/entitlements/entitlement_provider.dart';
import 'core/local/local_database.dart';
import 'core/tenant_access/tenant_access_provider.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  try {
    // Complete process initialization behind the native splash. The splash is
    // removed later, only after GoRouter has resolved the required first page.
    await _initializeApp();
    runApp(const ProviderScope(child: MobileShopApp()));
    unawaited(
      LocalDatabase.initialize().catchError((Object error, StackTrace stack) {
        debugPrint('Local database initialization failed: $error');
        debugPrintStack(stackTrace: stack);
      }),
    );
  } catch (error, stack) {
    debugPrint('Application initialization failed: $error');
    debugPrintStack(stackTrace: stack);
    runApp(const _InitializationErrorApp());
    binding.addPostFrameCallback((_) => FlutterNativeSplash.remove());
  }
}

Future<void> _initializeApp() async {
  await Future.wait([
    Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    ),
    SharedPreferences.getInstance(),
  ]);
}

class _InitializationErrorApp extends StatelessWidget {
  const _InitializationErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        body: Center(
          child: Padding(padding: EdgeInsets.all(24), child: _StartupError()),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.error),
        const SizedBox(height: 16),
        const Text(AppStrings.somethingWentWrong, textAlign: TextAlign.center),
      ],
    );
  }
}

class MobileShopApp extends ConsumerStatefulWidget {
  const MobileShopApp({super.key});

  @override
  ConsumerState<MobileShopApp> createState() => _MobileShopAppState();
}

class _MobileShopAppState extends ConsumerState<MobileShopApp> {
  bool _handoffStarted = false;

  void _startSplashHandoff() {
    if (_handoffStarted) return;
    _handoffStarted = true;

    // Keep the one native splash visible while the resolved destination builds
    // and starts its providers. Do not insert a second Flutter splash screen.
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authListenerProvider);
    ref.watch(permissionRealtimeRefreshProvider);
    ref.watch(entitlementRealtimeRefreshProvider);
    // Temporarily disabled: this schedules a permission refresh 30 seconds
    // after startup/resume and can make the current screen appear to reload.
    // ref.watch(permissionSafetyRefreshProvider);
    ref.watch(tenantAccessRealtimeProvider);
    ref.watch(tenantAccessSafetyRefreshProvider);
    ref.watch(mobileServiceAutoSyncProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppStrings.appName,
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final path = router.routerDelegate.currentConfiguration.uri.path;
        if (path != '/') _startSplashHandoff();

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppColors.background,
              child: child ?? const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}
