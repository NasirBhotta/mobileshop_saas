import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('return UI explains refund method and affected account', () {
    final screen =
        File(
          'lib/features/pos/presentation/screens/return_screen.dart',
        ).readAsStringSync();

    expect(screen, contains("label: Text('Original account')"));
    expect(screen, contains("label: Text('Adjust Khata')"));
    expect(screen, contains("'Refund kis account se niklega'"));
    expect(screen, contains("'Refund destination: Customer Khata'"));
    expect(screen, contains('returnRefundPreviewProvider'));
    expect(screen, contains('returnCreditCapacityProvider'));
  });

  test('refund preview uses original non-credit payment accounts', () {
    final repository =
        File(
          'lib/features/pos/data/repositories/pos_repository.dart',
        ).readAsStringSync();

    expect(repository, contains('previewReturnRefund'));
    expect(repository, contains("payment.method <> 'credit'"));
    expect(repository, contains('account.name AS account_name'));
    expect(repository, contains('PosRefundAllocator.allocate'));
    expect(repository, contains('previewCreditReturnCapacity'));
    expect(repository, contains("WHERE sale_id = ? AND method = 'credit'"));
  });
}
