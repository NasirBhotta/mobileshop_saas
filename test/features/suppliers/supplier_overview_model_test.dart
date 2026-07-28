import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';

void main() {
  test(
    'overview keeps order, receipt, payment and payable meanings separate',
    () {
      final now = DateTime(2026, 7, 28);
      final supplier = SupplierModel(
        id: 'supplier-1',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        name: 'Parts Supplier',
        outstandingBalance: 3000,
      );
      final overview = SupplierOverviewModel(
        supplier: supplier,
        purchaseOrders: [
          PurchaseOrderModel(
            id: 'po-1',
            tenantId: 'tenant-1',
            branchId: 'branch-1',
            supplierId: supplier.id,
            poNo: 'PO-1',
            status: PurchaseOrderStatus.partiallyReceived,
            totalExpectedCost: 10000,
            totalReceivedCost: 7000,
            createdAt: now,
          ),
        ],
        ledgerEntries: [
          _entry(
            id: 'receipt',
            direction: SupplierLedgerDirection.increase,
            type: 'goods_receipt',
            amount: 7000,
            at: now,
          ),
          _entry(
            id: 'payment',
            direction: SupplierLedgerDirection.decrease,
            type: 'supplier_payment',
            amount: 4000,
            at: now.add(const Duration(hours: 1)),
          ),
        ],
      );

      expect(overview.totalOrdered, 10000);
      expect(overview.totalReceived, 7000);
      expect(overview.pendingOrderValue, 3000);
      expect(overview.totalPaid, 4000);
      expect(overview.statementBalance, 3000);
      expect(overview.supplier.outstandingBalance, 3000);
      expect(overview.hasStatementMismatch, isFalse);
      expect(overview.openOrderCount, 1);
    },
  );

  test(
    'legacy payable mismatch is exposed instead of silently overwritten',
    () {
      const supplier = SupplierModel(
        id: 'supplier-1',
        tenantId: 'tenant-1',
        name: 'Legacy Supplier',
        outstandingBalance: 5000,
      );
      final overview = SupplierOverviewModel(
        supplier: supplier,
        purchaseOrders: const [],
        ledgerEntries: const [],
      );

      expect(overview.supplier.outstandingBalance, 5000);
      expect(overview.statementBalance, 0);
      expect(overview.hasStatementMismatch, isTrue);
    },
  );
}

SupplierLedgerEntryModel _entry({
  required String id,
  required SupplierLedgerDirection direction,
  required String type,
  required double amount,
  required DateTime at,
}) {
  return SupplierLedgerEntryModel(
    id: id,
    tenantId: 'tenant-1',
    branchId: 'branch-1',
    supplierId: 'supplier-1',
    entryType: type,
    direction: direction,
    amount: amount,
    sourceEventKey: 'supplier:$id',
    referenceType: type,
    referenceId: id,
    occurredAt: at,
    createdAt: at,
  );
}
