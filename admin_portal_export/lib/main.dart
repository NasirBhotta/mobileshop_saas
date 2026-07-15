import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/admin_portal_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AdminPortalConfig.validate();
  await Supabase.initialize(
    url: AdminPortalConfig.supabaseUrl,
    publishableKey: AdminPortalConfig.supabaseAnonKey,
  );
  runApp(const ProviderScope(child: PlatformAdminApp()));
}
