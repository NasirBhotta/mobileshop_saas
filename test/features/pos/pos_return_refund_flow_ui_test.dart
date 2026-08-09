import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('return UI explains refund method and affected account', () {
    final screen =
        File(
          'lib/features/pos/presentation/screens/return_screen.dart',
        ).readAsStringSync();

    expect(screen, contains("label: Text('Account refund')"));
    expect(screen, contains("labelText: 'Refund kis account se dena hai'"));
    expect(screen, contains("label: Text('Adjust Khata')"));
    expect(screen, contains("'Refund kis account se niklega'"));
    expect(screen, contains("'Refund destination: Customer Khata'"));
    expect(screen, contains('draft.cashRefundOptions'));
    expect(screen, contains('draft.creditRefundCapacity'));
    expect(screen, contains('WidgetsBinding.instance.addPostFrameCallback'));
  });

  test('refund preview uses original non-credit payment accounts', () {
    final repository =
        File(
          'lib/features/pos/data/repositories/pos_repository.dart',
        ).readAsStringSync();

    expect(repository, contains('previewReturnRefund'));
    expect(repository, contains('loadCashRefundOptions'));
    expect(repository, contains("payment.method <> 'credit'"));
    expect(repository, contains('account.name AS account_name'));
    expect(repository, contains('PosRefundAllocator.allocate'));
    expect(repository, contains('previewCreditReturnCapacity'));
    expect(repository, contains("WHERE sale_id = ? AND method = 'credit'"));
    expect(
      repository,
      contains('static const _returnSyncTimeout = Duration(seconds: 8)'),
    );
  });

  test('refund account choice survives pending approval', () {
    final model =
        File(
          'lib/features/pos/data/models/sale_return_model.dart',
        ).readAsStringSync();
    final migration =
        File(
          'supabase/migrations/20260809000400_pos_return_refund_account_selection.sql',
        ).readAsStringSync();

    expect(model, contains("'refund_payment_id': refundPaymentId"));
    expect(migration, contains('add column if not exists refund_payment_id'));
    expect(migration, contains('references public.sale_payments(id)'));
  });

  test('return completion invalidates account and transaction caches', () {
    final provider =
        File(
          'lib/features/pos/presentation/providers/pos_provider.dart',
        ).readAsStringSync();

    expect(provider, contains('_ref.invalidate(accountsProvider)'));
    expect(provider, contains('_ref.invalidate(accountTransactionsProvider)'));
  });
}
