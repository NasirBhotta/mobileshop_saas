import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PO reversal is atomic, guarded and auditable', () {
    final sql =
        File(
          'supabase/migrations/20260729000400_safe_purchase_order_reversal.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('reverse_purchase_order_v1'));
    expect(sql, contains('purchase_order_reversals'));
    expect(sql, contains('supplier_advances'));
    expect(sql, contains('quantity >= v_item.quantity for update'));
    expect(sql, contains('quantity=quantity-v_item.quantity'));
    expect(sql, contains('current_balance=current_balance+v_recovered'));
    expect(
      sql,
      contains('received stock has been sold, transferred, or consumed'),
    );
    expect(sql, contains("update public.products set is_active=false"));
    expect(sql, contains("'purchase_return'"));
  });

  test('PO UI separates unreceived cancellation from supplier return', () {
    final screen =
        File(
          'lib/features/suppliers/presentation/screens/purchase_orders_screen.dart',
        ).readAsStringSync();

    expect(screen, contains("'Return to Supplier'"));
    expect(screen, contains("'Cancel PO'"));
    expect(screen, contains("'Supplier Credit'"));
    expect(screen, contains("'Money Refunded'"));
    expect(screen, contains("'Refund received in account / wallet'"));
    expect(screen, contains("'Reversing...'"));
    expect(
      screen,
      isNot(contains('ref.watch(purchaseOrderControllerProvider).isLoading')),
    );
    expect(
      screen,
      contains(
        "'PO reversal database migration remote Supabase par apply nahi hui.'",
      ),
    );
    expect(screen, contains('_safeBackendMessage(raw)'));
    expect(screen, contains("message.split(', code:').first.trim()"));
  });
}
