import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/reports/domain/report_entitlement_gate.dart';

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

bool isEntitledActionVisible(bool? enabled) => enabled != false;

Future<bool> hasFeatureWithCompatibility(
  EntitlementEvaluator evaluator,
  String key,
) async {
  if (!key.startsWith('procurement.')) return evaluator.hasFeature(key);
  final specific = await evaluator.evaluateFeature(key);
  return specific.source == EntitlementValueSource.unavailable
      ? evaluator.hasFeature('purchases.procurement')
      : specific.isEnabled;
}

final compatibleFeatureEntitlementProvider =
    FutureProvider.family<bool, String>((ref, key) {
      ref.watch(entitlementRevisionProvider);
      return hasFeatureWithCompatibility(
        ref.watch(entitlementEvaluatorProvider),
        key,
      );
    });

final reportFeatureEntitlementProvider = FutureProvider.family<bool, String>((
  ref,
  key,
) {
  ref.watch(entitlementRevisionProvider);
  return ReportEntitlementGate(
    ref.watch(entitlementEvaluatorProvider),
  ).allows(key);
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
    'features',
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

const inventoryActionRouteEntitlements = <String, String>{
  '/inventory/import': 'inventory.csv_import',
  '/inventory/adjust': 'inventory.stock_adjustments',
};

const posActionRouteEntitlements = <String, String>{
  '/pos/return': 'pos.returns',
  '/pos/reprint': 'pos.receipt_printing',
};

const repairProcurementRouteEntitlements = <String, String>{
  '/purchase-orders/receive': 'procurement.goods_receipts',
  '/repairs': 'repairs.tickets',
  '/suppliers': 'procurement.suppliers',
  '/purchase-orders': 'procurement.purchase_orders',
};

const expenseAccountRouteEntitlements = <String, String>{
  '/expenses/recurring': 'expenses.recurring',
  '/expenses/report': 'expenses.reporting',
  '/expenses': 'expenses.core',
  '/accounts': 'accounts.core',
};

const reportRouteEntitlements = <String, String>{
  '/reports/sales/schedules': 'reports.scheduled',
  '/reports/business/schedules': 'reports.scheduled',
  '/reports/schedules': 'reports.scheduled',
  '/reports/sales': 'reports.sales',
  '/reports/business': 'reports.business',
  '/reports/profit-loss': 'reports.business',
  '/reports/inventory': 'reports.business',
  '/reports/customer-credit': 'reports.business',
  '/reports/cash-flow': 'reports.business',
  '/reports/repairs': 'reports.business',
};

String? requiredFeatureForLocation(String location) {
  for (final entry in reportRouteEntitlements.entries) {
    if (location == entry.key || location.startsWith('${entry.key}/')) {
      return entry.value;
    }
  }
  for (final entry in expenseAccountRouteEntitlements.entries) {
    if (location == entry.key || location.startsWith('${entry.key}/')) {
      return entry.value;
    }
  }
  for (final entry in repairProcurementRouteEntitlements.entries) {
    if (location == entry.key || location.startsWith('${entry.key}/')) {
      return entry.value;
    }
  }
  for (final entry in posActionRouteEntitlements.entries) {
    if (location == entry.key || location.startsWith('${entry.key}/')) {
      return entry.value;
    }
  }
  for (final entry in inventoryActionRouteEntitlements.entries) {
    if (location == entry.key || location.startsWith('${entry.key}/')) {
      return entry.value;
    }
  }
  String? match;
  for (final prefix in routeFeatureEntitlements.keys) {
    if ((location == prefix || location.startsWith('$prefix/')) &&
        (match == null || prefix.length > match.length)) {
      match = prefix;
    }
  }
  return match == null ? null : routeFeatureEntitlements[match];
}
