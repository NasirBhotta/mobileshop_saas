import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supplier payment is allocated and capped per received PO', () {
    final sql =
        File(
          'supabase/migrations/'
          '20260729000800_supplier_payment_po_allocation.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('add column if not exists purchase_order_id uuid'));
    expect(sql, contains('record_supplier_payment_v3'));
    expect(sql, contains('total_received_cost'));
    expect(sql, contains('payment exceeds purchase order pending amount'));
    expect(sql, contains('record_supplier_payment_v2'));
    expect(sql, contains('deferrable initially deferred'));
  });
}
