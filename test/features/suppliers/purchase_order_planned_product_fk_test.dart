import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('create-on-receipt may reserve a product id before product creation', () {
    final sql =
        File(
          'supabase/migrations/'
          '20260729000700_fix_po_planned_product_fk.sql',
        ).readAsStringSync().toLowerCase();

    expect(
      sql,
      contains(
        'drop constraint if exists po_items_resolved_product_id_fkey',
      ),
    );
    expect(sql, contains('validated by receive_purchase_order_goods'));
  });
}
