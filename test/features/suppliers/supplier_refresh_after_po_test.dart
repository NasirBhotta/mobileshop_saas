import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PO mutations invalidate supplier list and overview caches', () {
    final source =
        File(
          'lib/features/suppliers/presentation/providers/'
          'procurement_provider.dart',
        ).readAsStringSync();

    final createPo = source.substring(
      source.indexOf('Future<PurchaseOrderModel?> createPO'),
      source.indexOf('Future<void> markSent'),
    );

    expect(createPo, contains('invalidate(purchaseOrdersProvider)'));
    expect(createPo, contains('invalidate(suppliersProvider)'));
    expect(createPo, contains('invalidate(supplierOverviewProvider)'));
  });
}
