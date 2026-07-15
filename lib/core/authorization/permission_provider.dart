import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'permission_evaluator.dart';
import 'supabase_permission_data_source.dart';

final permissionDataSourceProvider = Provider<PermissionDataSource>((ref) {
  return SupabasePermissionDataSource();
});

final permissionEvaluatorProvider = Provider<PermissionEvaluator>((ref) {
  return PermissionEvaluator(
    dataSource: ref.watch(permissionDataSourceProvider),
  );
});
