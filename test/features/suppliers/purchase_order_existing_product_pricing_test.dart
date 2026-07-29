import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('existing PO item offers safe cost and separate-product modes', () {
    final source =
        File(
          'lib/features/suppliers/presentation/screens/'
          'purchase_order_form_screen.dart',
        ).readAsStringSync();

    expect(source, contains('enum _ExistingProductPricing'));
    expect(source, contains('Use current cost • add to same product'));
    expect(
      source,
      contains('Override cost • create cost variant if different'),
    );
    expect(
      source,
      contains('Different cost & sale price • create separate product'),
    );
    expect(source, contains('product.costPrice.toStringAsFixed(2)'));
    expect(source, contains('product.salePrice.toStringAsFixed(2)'));
    expect(
      source,
      contains('PurchaseProductResolution.createOnReceipt'),
      reason: 'separate variants must use the offline-safe receipt workflow',
    );
    expect(source, contains("'sale_price':"));
    expect(source, contains("'name':"));
  });
}
