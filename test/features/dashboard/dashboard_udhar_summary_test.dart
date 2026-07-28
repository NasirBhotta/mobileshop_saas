import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('udhar summary shows only the current outstanding amount', () {
    final dashboard =
        File(
          'lib/features/dashboard/presentation/screens/dashboard_screen.dart',
        ).readAsStringSync();

    expect(dashboard, contains("'Current pending udhar'"));
    expect(dashboard, isNot(contains("'Total udhar sales:")));
    expect(
      dashboard,
      isNot(contains('totalCreditSales: stats!.totalCreditSales')),
    );
  });
}
