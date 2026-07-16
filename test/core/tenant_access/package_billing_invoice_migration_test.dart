import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260716000400_package_billing_invoices.sql',
    ).readAsStringSync().toLowerCase();
  });

  test('invoice stores immutable package and billing snapshots', () {
    for (final column in const [
      'plan_id',
      'plan_key_snapshot',
      'plan_name_snapshot',
      'billing_cycle',
      'original_amount',
      'discount_amount',
      'service_months',
    ]) {
      expect(sql, contains(column));
    }
  });

  test('package invoice RPC validates tenant, plan, amount and discount', () {
    expect(sql, contains('platform_create_package_invoice'));
    expect(sql, contains('active package not found'));
    expect(sql, contains('invoice amount must be greater than zero'));
    expect(sql, contains('discount must be non-negative'));
  });

  test('invoice creation is audited and does not activate subscription', () {
    expect(sql, contains('billing.invoice_created'));
    expect(sql, isNot(contains("set status = 'active'")));
  });
}
