import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both repair payment actions reflect controller loading state', () {
    final source =
        File(
          'lib/features/repairs/presentation/screens/repairs_list_screen.dart',
        ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      source,
      contains(
        'repairPaymentControllerProvider.select((state) => state.isLoading)',
      ),
    );
    expect(source, contains('AppStrings.repairReceivingPayment'));
    expect(source, contains('_isSaving || isReceivingPayment'));
    expect(source, contains('isReceivingPayment\n'));
  });
}
