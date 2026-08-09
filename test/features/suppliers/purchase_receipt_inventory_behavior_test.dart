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

  test('PO reversal refreshes local inventory before invalidation', () {
    final provider =
        File(
          'lib/features/suppliers/presentation/providers/procurement_provider.dart',
        ).readAsStringSync();
    final reverseStart = provider.indexOf('Future<bool> reversePO');
    final reverseEnd = provider.indexOf(
      'final receiveGoodsControllerProvider',
      reverseStart,
    );
    final reverseFlow = provider.substring(reverseStart, reverseEnd);

    expect(reverseFlow, contains('refreshCurrentProductsCache()'));
    expect(reverseFlow, contains('invalidateProductListProviders(_ref);'));
    expect(
      reverseFlow.indexOf('refreshCurrentProductsCache()'),
      lessThan(reverseFlow.indexOf('invalidateProductListProviders(_ref);')),
    );

    final repository =
        File(
          'lib/features/suppliers/data/repositories/procurement_repository.dart',
        ).readAsStringSync();
    final localStore =
        File(
          'lib/features/suppliers/data/local/procurement_local_store.dart',
        ).readAsStringSync();
    expect(repository, contains('reconcileReversedPurchaseOrderInventory'));
    expect(repository, isNot(contains('deactivateCachedProduct')));
    expect(localStore, contains('quantity = MAX(quantity - ?, 0)'));
    expect(localStore, isNot(contains('UPDATE products SET is_active = 0')));
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
