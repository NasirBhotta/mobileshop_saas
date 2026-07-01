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

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  debugPrint("flutter native splash is running");
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await _initializeApp();

  FlutterNativeSplash.remove();

  runApp(const ProviderScope(child: MobileShopApp()));
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
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppStrings.appName,
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
