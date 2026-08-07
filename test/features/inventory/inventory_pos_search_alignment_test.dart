import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/inventory/presentation/providers/inventory_provider.dart';

void main() {
  test('inventory and POS use aligned debounce and result batch size', () {
    final inventory =
        File(
          'lib/features/inventory/presentation/screens/inventory_screen.dart',
        ).readAsStringSync();
    final pos =
        File(
          'lib/features/pos/presentation/widgets/product_search_panel.dart',
        ).readAsStringSync();

    expect(inventory, contains('_searchDelay = Duration(milliseconds: 250)'));
    expect(pos, contains('Duration(milliseconds: 250)'));
    expect(inventory, contains('static const _pageSize = 50'));
    expect(const InventoryProductsRequest(query: '').limit, 50);
  });

  test('POS accepts one-character searches like inventory', () {
    final provider =
        File(
          'lib/features/inventory/presentation/providers/inventory_provider.dart',
        ).readAsStringSync();
    final pos =
        File(
          'lib/features/pos/presentation/widgets/product_search_panel.dart',
        ).readAsStringSync();

    expect(provider, isNot(contains('query.length < 2')));
    expect(pos, isNot(contains('Kam az kam 2 characters')));
  });

  test(
    'sale product search keeps current results during background loading',
    () {
      final pos =
          File(
            'lib/features/pos/presentation/widgets/product_search_panel.dart',
          ).readAsStringSync();

      expect(pos, contains('productsAsync.isLoading && _lastProducts != null'));
      expect(
        pos,
        contains('AsyncValue<List<ProductModel>>.data(_lastProducts!)'),
      );
      expect(pos, contains('_lastProducts = products;'));
    },
  );
}
