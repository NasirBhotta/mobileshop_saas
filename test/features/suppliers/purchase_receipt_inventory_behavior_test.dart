import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goods receipt refreshes inventory product lists immediately', () {
    final provider =
        File(
          'lib/features/suppliers/presentation/providers/procurement_provider.dart',
        ).readAsStringSync();
    expect(provider, contains('refreshCurrentProductsCache()'));
    expect(provider, contains('invalidateProductListProviders(_ref);'));
  });

  test('different actual cost is routed to a separate product variant', () {
    final sql =
        File(
          'supabase/migrations/20260721000100_receive_stock_by_actual_cost.sql',
        ).readAsStringSync();

    expect(sql, contains('source_product_id uuid'));
    expect(sql, contains('p.cost_price = v_item.actual_unit_cost'));
    expect(sql, contains('v_inventory_product_id := gen_random_uuid()'));
    expect(sql, contains('v_inventory_product_id, v_item.received_quantity'));
    expect(sql, isNot(contains('set cost_price = v_item.actual_unit_cost')));

    final localStore =
        File(
          'lib/features/suppliers/data/local/procurement_local_store.dart',
        ).readAsStringSync();
    expect(localStore, contains('sameCost ||'));
    expect(localStore, contains('do not corrupt the original product'));
  });
}
