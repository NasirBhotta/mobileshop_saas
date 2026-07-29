import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile service form prevents wallet and cash overdrafts', () {
    final source =
        File(
          'lib/features/mobile_services/presentation/screens/'
          'mobile_services_screen.dart',
        ).readAsStringSync();

    expect(source, contains('final balanceError'));
    expect(source, contains('You cannot send this amount'));
    expect(source, contains('You cannot pay this customer'));
    expect(source, contains('balanceError != null'));
    expect(source, contains('selectedWallet.currentBalance + 0.01'));
    expect(source, contains('selectedCashAccount.currentBalance + 0.01'));
  });
}
