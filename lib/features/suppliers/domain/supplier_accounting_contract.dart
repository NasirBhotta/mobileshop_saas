enum PurchaseProductResolution {
  existingProduct,
  createOnReceipt,
  resolveOnReceipt,
  directUse,
}

extension PurchaseProductResolutionX on PurchaseProductResolution {
  String get code => switch (this) {
    PurchaseProductResolution.existingProduct => 'existing_product',
    PurchaseProductResolution.createOnReceipt => 'create_on_receipt',
    PurchaseProductResolution.resolveOnReceipt => 'resolve_on_receipt',
    PurchaseProductResolution.directUse => 'direct_use',
  };

  String get label => switch (this) {
    PurchaseProductResolution.existingProduct => 'Existing inventory product',
    PurchaseProductResolution.createOnReceipt => 'Create product on receipt',
    PurchaseProductResolution.resolveOnReceipt => 'Choose product on receipt',
    PurchaseProductResolution.directUse => 'Direct use (no inventory)',
  };

  static PurchaseProductResolution fromCode(String? code) => switch (code) {
    'create_on_receipt' => PurchaseProductResolution.createOnReceipt,
    'resolve_on_receipt' => PurchaseProductResolution.resolveOnReceipt,
    'direct_use' => PurchaseProductResolution.directUse,
    _ => PurchaseProductResolution.existingProduct,
  };
}

enum SupplierBusinessEvent {
  purchaseOrder,
  goodsReceipt,
  supplierPayment,
  purchaseReturn,
  creditNote,
  paymentReversal,
}

class SupplierAccountingEffect {
  final int inventoryDirection;
  final int payableDirection;
  final int moneyDirection;

  const SupplierAccountingEffect({
    required this.inventoryDirection,
    required this.payableDirection,
    required this.moneyDirection,
  });
}

abstract final class SupplierAccountingContract {
  static const effects = <SupplierBusinessEvent, SupplierAccountingEffect>{
    SupplierBusinessEvent.purchaseOrder: SupplierAccountingEffect(
      inventoryDirection: 0,
      payableDirection: 0,
      moneyDirection: 0,
    ),
    SupplierBusinessEvent.goodsReceipt: SupplierAccountingEffect(
      inventoryDirection: 1,
      payableDirection: 1,
      moneyDirection: 0,
    ),
    SupplierBusinessEvent.supplierPayment: SupplierAccountingEffect(
      inventoryDirection: 0,
      payableDirection: -1,
      moneyDirection: -1,
    ),
    SupplierBusinessEvent.purchaseReturn: SupplierAccountingEffect(
      inventoryDirection: -1,
      payableDirection: -1,
      moneyDirection: 0,
    ),
    SupplierBusinessEvent.creditNote: SupplierAccountingEffect(
      inventoryDirection: 0,
      payableDirection: -1,
      moneyDirection: 0,
    ),
    SupplierBusinessEvent.paymentReversal: SupplierAccountingEffect(
      inventoryDirection: 0,
      payableDirection: 1,
      moneyDirection: 1,
    ),
  };

  static bool requiresInventoryProduct(PurchaseProductResolution resolution) {
    return resolution == PurchaseProductResolution.existingProduct ||
        resolution == PurchaseProductResolution.createOnReceipt;
  }

  static bool mayCompleteReceipt({
    required PurchaseProductResolution resolution,
    required bool hasResolvedProduct,
  }) {
    if (resolution == PurchaseProductResolution.directUse) return true;
    return hasResolvedProduct;
  }
}
