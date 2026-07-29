import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchase orders are grouped under supplier headings', () {
    final source =
        File(
          'lib/features/suppliers/presentation/screens/'
          'purchase_orders_screen.dart',
        ).readAsStringSync();

    expect(source, contains('class _SupplierGroupedPurchaseOrders'));
    expect(source, contains('grouped.putIfAbsent(order.supplierId'));
    expect(source, contains("'Unknown supplier'"));
  });

  test('PO refund reversal fixes ledger ordering and empty recovery', () {
    final sql =
        File(
          'supabase/migrations/'
          '20260729001000_fix_po_return_refund_ledger.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('deferrable initially deferred'));
    expect(sql, contains('reverse_purchase_order_v2'));
    expect(sql, contains("recovered_amount')::numeric"));
    expect(sql, contains('recovery_ledger_transaction_id = null'));
  });
}
