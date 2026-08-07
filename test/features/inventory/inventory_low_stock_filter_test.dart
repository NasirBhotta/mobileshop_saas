import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/extensions/product_sort_ext.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';

void main() {
  test('low-stock flag participates in paged request identity', () {
    const normal = InventoryProductsRequest(
      query: 'samsung',
      categoryId: 'phones',
      sortOption: ProductSortOption.stockLow,
      limit: 100,
    );
    const lowStock = InventoryProductsRequest(
      query: 'samsung',
      categoryId: 'phones',
      sortOption: ProductSortOption.stockLow,
      limit: 100,
      lowStockOnly: true,
    );

    expect(normal, isNot(lowStock));
    expect(normal.hashCode, isNot(lowStock.hashCode));
  });

  test('dashboard route and both inventory data paths use low-stock filter', () {
    final dashboard =
        File(
          'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
        ).readAsStringSync();
    final repository =
        File(
          'lib/features/inventory/data/repositories/inventory_repository.dart',
        ).readAsStringSync();
    final localStore =
        File('lib/core/local/local_store.dart').readAsStringSync();

    expect(dashboard, contains("route: '/inventory?stock=low'"));
    expect(repository, contains(".eq('is_low_stock', true)"));
    expect(localStore, contains('COALESCE(i.quantity, 0) > 0'));
    expect(localStore, contains('NULLIF(c.default_reorder_threshold, 0)'));
  });
}
