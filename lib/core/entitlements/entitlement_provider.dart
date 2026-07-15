import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entitlement_evaluator.dart';
import 'supabase_entitlement_data_source.dart';

final entitlementDataSourceProvider = Provider<EntitlementDataSource>((ref) {
  return SupabaseEntitlementDataSource();
});

final entitlementEvaluatorProvider = Provider<EntitlementEvaluator>((ref) {
  return EntitlementEvaluator(
    dataSource: ref.watch(entitlementDataSourceProvider),
  );
});
