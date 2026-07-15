import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/admin_router.dart';
import 'theme/admin_theme.dart';

class PlatformAdminApp extends ConsumerWidget {
  const PlatformAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Platform Admin',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light,
      routerConfig: ref.watch(adminRouterProvider),
    );
  }
}
