import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';

void main() {
  test('supplier analytics derives profit without changing operational totals', () {
    const product = SupplierProductAnalyticsModel(
      productId: 'product-1',
      productName: 'Phone',
      lastPurchaseCost: 800,
      stockOnHand: 3,
      soldQuantity: 2,
      salesRevenue: 2200,
      costOfSales: 1600,
    );
    const analytics = SupplierSalesAnalyticsModel(
      products: [product],
      linkedProductCount: 1,
      soldQuantity: 2,
      revenue: 2200,
      costOfSales: 1600,
    );

    expect(product.grossProfit, 600);
    expect(analytics.grossProfit, 600);
  });

  test('analytics remains a read-only supplier UI query', () {
    final repository = File(
      'lib/features/suppliers/data/repositories/procurement_repository.dart',
    ).readAsStringSync();
    final method = repository.substring(
      repository.indexOf('fetchSupplierSalesAnalytics'),
      repository.indexOf('Future<List<SupplierModel>> _fetchRemoteSuppliers'),
    );

    expect(method, contains(".from('supplier_products')"));
    expect(method, contains(".from('sales')"));
    expect(method, isNot(contains('.insert(')));
    expect(method, isNot(contains('.update(')));
    expect(method, isNot(contains('.delete(')));
    expect(method, isNot(contains('.rpc(')));
  });
}
