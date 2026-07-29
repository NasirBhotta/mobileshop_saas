import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supplier offline queue is serialized and dependency aware', () {
    final source =
        File(
          'lib/features/suppliers/data/repositories/'
          'procurement_repository.dart',
        ).readAsStringSync();

    for (final mutation in [
      'upsert_supplier',
      'create_purchase_order',
      'mark_po_sent',
      'receive_po_goods',
      'record_supplier_payment',
      'reverse_purchase_order',
    ]) {
      expect(source, contains("'$mutation'"));
    }

    expect(source, contains('_procurementSyncInFlight'));
    expect(source, contains('failedSupplierIds'));
    expect(source, contains('failedPurchaseOrderIds'));
    expect(source, contains('_hasPendingProcurementMutations'));
    expect(source, contains('_syncThenRefreshPurchaseOrders'));
    expect(
      source,
      contains('Received PO return needs internet'),
      reason: 'financially complex offline returns must fail safely',
    );
  });
}
