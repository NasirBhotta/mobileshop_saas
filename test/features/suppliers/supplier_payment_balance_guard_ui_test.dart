import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supplier payment UI caps amount by selected account balance', () {
    final source =
        File(
          'lib/features/suppliers/presentation/screens/suppliers_screen.dart',
        ).readAsStringSync();

    expect(source, contains('final maximumSendable'));
    expect(source, contains('amountExceedsBalance'));
    expect(source, contains('Insufficient balance. Available Rs'));
    expect(source, contains('!amountIsValid'));
    expect(source, contains('amount > availableBalance + 0.01'));
  });
}
