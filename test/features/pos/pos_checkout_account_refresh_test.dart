import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful checkout invalidates account balance and ledger caches', () {
    final provider =
        File(
          'lib/features/pos/presentation/providers/pos_provider.dart',
        ).readAsStringSync();
    final checkoutStart = provider.indexOf('Future<SaleModel?> checkout()');
    final holdCartStart = provider.indexOf(
      'Future<bool> holdCart',
      checkoutStart,
    );
    final checkout = provider.substring(checkoutStart, holdCartStart);

    expect(checkout, contains('_ref.invalidate(accountsProvider)'));
    expect(checkout, contains('_ref.invalidate(accountTransactionsProvider)'));
    expect(
      checkout.indexOf('_repository.checkout('),
      lessThan(checkout.indexOf('_ref.invalidate(accountsProvider)')),
    );
  });
}
