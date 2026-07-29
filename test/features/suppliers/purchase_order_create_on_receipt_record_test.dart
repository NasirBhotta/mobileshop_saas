import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('create-on-receipt never dereferences an unassigned record', () {
    final migration =
        File(
          'supabase/migrations/20260729000300_fix_create_on_receipt_unassigned_record.sql',
        ).readAsStringSync().toLowerCase();

    expect(migration, contains('v_existing_product_name text'));
    expect(migration, contains('v_existing_product_sku text'));
    expect(migration, contains('v_existing_product_sku := null'));
    expect(migration, isNot(contains('v_product record')));
    expect(migration, isNot(contains('v_product.sku')));
    expect(migration, contains("v_resolution = 'create_on_receipt'"));
    expect(migration, contains('else v_item.product_sku end'));
  });
}
