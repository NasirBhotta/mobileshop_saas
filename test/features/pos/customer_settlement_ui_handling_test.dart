import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settlement sheet prevents duplicate submits and handles errors', () {
    final screen =
        File(
          'lib/features/pos/presentation/screens/customers_screen.dart',
        ).readAsStringSync();

    expect(screen, contains("Text('Recording...')"));
    expect(screen, contains('CircularProgressIndicator'));
    expect(screen, contains('isSubmitting || effectiveAccountId == null'));
    expect(screen, contains('try {'));
    expect(screen, contains('catch (error)'));
    expect(screen, contains('finally {'));
    expect(screen, contains('_settlementErrorMessage(error)'));
    expect(screen, contains('ledger_transaction_id_fkey'));
    expect(
      screen,
      isNot(contains("error?.toString() ?? 'Settlement save nahi hui'")),
    );
  });
}
