import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260716000500_verify_payment_activate_package.sql',
    ).readAsStringSync().toLowerCase();
  });

  test('manual payment requires one matching open package invoice', () {
    expect(sql, contains('an open package invoice is required'));
    expect(sql, contains('only an open invoice can receive payment'));
    expect(
      sql,
      contains('payment must exactly match the invoice payable amount'),
    );
    expect(sql, contains("bp.status in ('recorded', 'verified')"));
  });

  test('duplicate open invoices are blocked and accidental ones can be voided', () {
    expect(sql, contains('prevent_multiple_open_billing_invoices'));
    expect(sql, contains('tenant already has an open invoice'));
    expect(sql, contains('platform_void_billing_invoice'));
    expect(sql, contains('review the linked payment before voiding this invoice'));
  });

  test('verification atomically pays invoice and activates its package', () {
    expect(sql, contains("set status = 'paid'"));
    expect(sql, contains('set plan_id = invoice.plan_id'));
    expect(sql, contains("status = 'active'"));
    expect(sql, contains('make_interval(months => invoice.service_months)'));
    expect(sql, contains('set plan = invoice.plan_key_snapshot'));
  });

  test('payment activation does not remove administrative suspension', () {
    expect(
      sql,
      contains('an administratively suspended tenant must remain suspended'),
    );
    expect(sql, isNot(contains("set status = 'active'\n    where id = pay.tenant_id")));
  });

  test('rejection leaves invoice open and subscription unchanged', () {
    expect(sql, contains("set status = 'rejected'"));
    final rejection = sql.substring(
      sql.indexOf('if not p_verified then'),
      sql.indexOf('else', sql.indexOf('if not p_verified then')),
    );
    expect(rejection, isNot(contains('billing_invoices')));
    expect(rejection, isNot(contains('tenant_subscriptions')));
  });
}
