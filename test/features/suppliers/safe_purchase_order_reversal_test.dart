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
    expect(sql, isNot(contains("update public.products set is_active=false")));
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
    expect(screen, contains('PO return offline nahi ho sakta'));
    expect(screen, isNot(contains('NetworkService().hasConnection')));
    expect(screen, contains('Is PO ki koi payment nahi hui'));
    expect(screen, contains('loadPaidForPurchaseOrder'));
  });

  test('deployed reversal fix is schema-safe and PO-payment-specific', () {
    final sql =
        File(
          'supabase/migrations/20260810000100_fix_po_reversal_product_timestamp.sql',
        ).readAsStringSync().toLowerCase();

    expect(sql, contains('add column if not exists updated_at'));
    expect(sql, contains('sp.purchase_order_id=p_po_id'));
    expect(sql, contains('v_received-coalesce(sum(sp.amount),0)'));
    expect(sql, contains('least(v_received,coalesce(sum(sp.amount),0))'));
    expect(
      sql,
      contains('create or replace function public.reverse_purchase_order_v1'),
    );
  });
}
