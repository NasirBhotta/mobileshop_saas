import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entitlement_evaluator.dart';
import 'supabase_entitlement_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final entitlementDataSourceProvider = Provider<EntitlementDataSource>((ref) {
  return SupabaseEntitlementDataSource();
});

final entitlementEvaluatorProvider = Provider<EntitlementEvaluator>((ref) {
  return EntitlementEvaluator(
    dataSource: ref.watch(entitlementDataSourceProvider),
  );
});

final entitlementRevisionProvider = NotifierProvider<EntitlementRevision, int>(
  EntitlementRevision.new,
);

class EntitlementRevision extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() {
    ref.read(entitlementEvaluatorProvider).invalidateAll();
    state++;
  }
}

final featureEntitlementProvider = FutureProvider.family<bool, String>((
  ref,
  key,
) {
  ref.watch(entitlementRevisionProvider);
  return ref.watch(entitlementEvaluatorProvider).hasFeature(key);
});

final entitlementRealtimeRefreshProvider = Provider<void>((ref) {
  final client = Supabase.instance.client;
  final channel = client.channel('tenant-entitlement-refresh');
  void refresh(PostgresChangePayload _) {
    ref.read(entitlementRevisionProvider.notifier).refresh();
  }

  for (final table in const [
    'tenant_subscriptions',
    'tenant_feature_overrides',
    'plan_features',
    'plans',
  ]) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: refresh,
    );
  }
  channel.subscribe();
  ref.onDispose(() => client.removeChannel(channel));
});

const routeFeatureEntitlements = <String, String>{
  '/dashboard': 'dashboard.access',
  '/inventory': 'inventory.access',
  '/pos': 'pos.access',
  '/customers': 'customers.access',
  '/repairs': 'repairs.access',
  '/suppliers': 'suppliers.access',
  '/purchase-orders': 'purchases.access',
  '/accounts': 'accounts.access',
  '/expenses': 'expenses.access',
  '/reports': 'reports.access',
  '/settings': 'settings.access',
};

String? requiredFeatureForLocation(String location) {
  String? match;
  for (final prefix in routeFeatureEntitlements.keys) {
    if ((location == prefix || location.startsWith('$prefix/')) &&
        (match == null || prefix.length > match.length)) {
      match = prefix;
    }
  }
  return match == null ? null : routeFeatureEntitlements[match];
}
