import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/suppliers/domain/supplier_accounting_contract.dart';

void main() {
  test('purchase order is commitment-only', () {
    final effect =
        SupplierAccountingContract.effects[SupplierBusinessEvent
            .purchaseOrder]!;
    expect(effect.inventoryDirection, 0);
    expect(effect.payableDirection, 0);
    expect(effect.moneyDirection, 0);
  });

  test('receipt adds stock and payable but never moves money', () {
    final effect =
        SupplierAccountingContract.effects[SupplierBusinessEvent.goodsReceipt]!;
    expect(effect.inventoryDirection, 1);
    expect(effect.payableDirection, 1);
    expect(effect.moneyDirection, 0);
  });

  test('supplier payment reduces payable and selected money account', () {
    final effect =
        SupplierAccountingContract.effects[SupplierBusinessEvent
            .supplierPayment]!;
    expect(effect.inventoryDirection, 0);
    expect(effect.payableDirection, -1);
    expect(effect.moneyDirection, -1);
  });

  test('unresolved stock cannot be silently received', () {
    expect(
      SupplierAccountingContract.mayCompleteReceipt(
        resolution: PurchaseProductResolution.resolveOnReceipt,
        hasResolvedProduct: false,
      ),
      isFalse,
    );
    expect(
      SupplierAccountingContract.mayCompleteReceipt(
        resolution: PurchaseProductResolution.directUse,
        hasResolvedProduct: false,
      ),
      isTrue,
    );
  });

  test('all product-resolution modes are wired through model and UI', () {
    final model =
        File(
          'lib/features/suppliers/data/models/procurement_models.dart',
        ).readAsStringSync();
    final form =
        File(
          'lib/features/suppliers/presentation/screens/purchase_order_form_screen.dart',
        ).readAsStringSync();
    final localStore =
        File(
          'lib/features/suppliers/data/local/procurement_local_store.dart',
        ).readAsStringSync();
    final repository =
        File(
          'lib/features/suppliers/data/repositories/procurement_repository.dart',
        ).readAsStringSync();

    expect(model, contains('final String? productId'));
    expect(model, contains("'product_resolution': productResolution.code"));
    expect(form, contains('PurchaseProductResolution.values'));
    expect(form, contains('PurchaseProductResolution.createOnReceipt'));
    expect(localStore, contains('updateSupplierBalance'));
    expect(
      localStore,
      contains('SupplierAccountingContract.mayCompleteReceipt'),
    );
    expect(
      RegExp("'product_resolution': e\\['product_resolution'\\]")
          .allMatches(repository),
      isNotEmpty,
    );
    expect(repository, contains("'resolved_product_id': e['resolved_product_id']"));
  });
}
