import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260809000300_secure_pos_checkout_and_discount_approval.sql',
  );

  test('discount PIN verification stays behind a hashed server RPC', () {
    final sql = migration.readAsStringSync().toLowerCase();

    expect(sql, contains('create extension if not exists pgcrypto'));
    expect(sql, contains('verify_pos_discount_approval'));
    expect(sql, contains("approval_pin = extensions.crypt("));
    expect(sql, contains("extensions.gen_salt('bf')"));
    expect(sql, contains("permission.key = 'pos.discount.approve'"));
    expect(
      sql,
      contains(
        'revoke execute on function public.commit_pos_sale(jsonb) from authenticated',
      ),
    );
  });

  test(
    'checkout validates item arithmetic before the established v2 commit',
    () {
      final sql = migration.readAsStringSync().toLowerCase();

      expect(sql, contains('validate_pos_sale_amounts'));
      expect(sql, contains('discount_amount > v_item.unit_price'));
      expect(sql, contains('sale totals do not match item calculations'));
      expect(sql, contains('perform public.validate_pos_sale_amounts(p_sale)'));
      expect(sql, contains('commit_pos_sale_v2_unvalidated(p_sale)'));
    },
  );

  test('client uses the approval RPC and never queries approval_pin', () {
    final repository =
        File(
          'lib/features/pos/data/repositories/pos_repository.dart',
        ).readAsStringSync();

    expect(repository, contains("'verify_pos_discount_approval'"));
    expect(repository, isNot(contains(".eq('approval_pin'")));
  });
}
