import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchase order export preserves the return navigation stack', () {
    final screen =
        File(
          'lib/features/suppliers/presentation/screens/purchase_orders_screen.dart',
        ).readAsStringSync();

    expect(
      screen,
      contains("context.push('/purchase-orders/export', extra: po)"),
    );
    expect(
      screen,
      isNot(contains("context.go('/purchase-orders/export', extra: po)")),
    );
  });
}
