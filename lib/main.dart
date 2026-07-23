import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobileshop_saas/features/auth/presentation/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/router/app_router.dart';
import 'config/supabase/supabase_config.dart';
import 'config/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/local/local_database.dart';
import 'core/tenant_access/tenant_access_provider.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  debugPrint("flutter native splash is running");
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await _initializeApp();

  runApp(const ProviderScope(child: MobileShopApp()));

  widgetsBinding.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
    unawaited(
      LocalDatabase.initialize().catchError((Object error, StackTrace stack) {
        debugPrint('Local database initialization failed: $error');
        debugPrintStack(stackTrace: stack);
      }),
    );
  });
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

class MobileShopApp extends ConsumerWidget {
  const MobileShopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authListenerProvider);
    ref.watch(tenantAccessRealtimeProvider);
    ref.watch(tenantAccessSafetyRefreshProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppStrings.appName,
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
