import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/suppliers/data/local/procurement_local_store.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/procurement_models.dart';
import 'package:mobileshop_saas/features/suppliers/domain/supplier_accounting_contract.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _tenantId = 'receipt-ledger-tenant';
const _branchId = 'receipt-ledger-branch';
const _supplierId = 'receipt-ledger-supplier';
const _productId = 'receipt-ledger-product';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('receipt-ledger-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return databaseDirectory.path;
          }
          return null;
        });
    await LocalDatabase.initialize();
    await ProcurementLocalStore.saveSupplier(
      const SupplierModel(
        id: _supplierId,
        tenantId: _tenantId,
        branchId: _branchId,
        name: 'Parts Supplier',
      ),
    );
    await LocalDatabase.execute(
      '''
      INSERT INTO products(
        id, tenant_id, branch_id, name, cost_price, is_active
      ) VALUES (?, ?, ?, 'Panel', 5000, 1)
      ''',
      [_productId, _tenantId, _branchId],
    );
  });

  setUp(() async {
    await LocalDatabase.execute('DELETE FROM supplier_ledger_entries');
    await LocalDatabase.execute('DELETE FROM goods_receipt_items');
    await LocalDatabase.execute('DELETE FROM goods_receipts');
    await LocalDatabase.execute('DELETE FROM purchase_order_items');
    await LocalDatabase.execute('DELETE FROM purchase_orders');
    await LocalDatabase.execute('DELETE FROM inventory');
    await LocalDatabase.execute(
      'UPDATE suppliers SET outstanding_balance = 0 WHERE id = ?',
      [_supplierId],
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('receipt retry adds stock, payable, and statement once', () async {
    final po = _purchaseOrder();
    await ProcurementLocalStore.savePurchaseOrder(po);
    const input = GoodsReceiptItemInput(
      purchaseOrderItemId: 'po-item',
      receivedQuantity: 2,
      actualUnitCost: 5000,
    );

    for (var i = 0; i < 2; i++) {
      await ProcurementLocalStore.applyReceiptLocally(
        po: po,
        receiptId: 'receipt-1',
        receiptNo: 'GR-1',
        userId: 'owner',
        inputs: const [input],
      );
    }

    final stock = await LocalDatabase.select(
      'SELECT quantity FROM inventory WHERE product_id = ?',
      [_productId],
    );
    final supplier = await LocalDatabase.select(
      'SELECT outstanding_balance FROM suppliers WHERE id = ?',
      [_supplierId],
    );
    expect((stock.single['quantity'] as num).toInt(), 2);
    expect((supplier.single['outstanding_balance'] as num).toDouble(), 10000);
    expect(
      await ProcurementLocalStore.calculateSupplierPayable(_supplierId),
      10000,
    );
    expect(
      await LocalDatabase.select('SELECT * FROM supplier_ledger_entries'),
      hasLength(1),
    );
    expect(
      await LocalDatabase.select('SELECT * FROM goods_receipt_items'),
      hasLength(1),
    );
  });

  test(
    'direct-use receipt creates payable without stock or money flow',
    () async {
      final po = _purchaseOrder(
        productId: null,
        resolution: PurchaseProductResolution.directUse,
      );
      await ProcurementLocalStore.savePurchaseOrder(po);
      final accountsBefore = await LocalDatabase.select(
        'SELECT * FROM account_transactions',
      );

      await ProcurementLocalStore.applyReceiptLocally(
        po: po,
        receiptId: 'direct-receipt',
        receiptNo: 'GR-DIRECT',
        userId: 'owner',
        inputs: const [
          GoodsReceiptItemInput(
            purchaseOrderItemId: 'po-item',
            receivedQuantity: 2,
            actualUnitCost: 5000,
          ),
        ],
      );

      expect(await LocalDatabase.select('SELECT * FROM inventory'), isEmpty);
      expect(
        await ProcurementLocalStore.calculateSupplierPayable(_supplierId),
        10000,
      );
      expect(
        await LocalDatabase.select('SELECT * FROM account_transactions'),
        hasLength(accountsBefore.length),
      );
    },
  );

  test(
    'create-on-receipt creates product, stock and payable atomically',
    () async {
      final po = _purchaseOrder(
        productId: null,
        resolution: PurchaseProductResolution.createOnReceipt,
        resolvedProductId: 'created-panel',
        productDraft: const {
          'name': 'OLED Panel',
          'sku': 'OLED-1',
          'sale_price': 8000,
        },
      );
      await ProcurementLocalStore.savePurchaseOrder(po);

      await ProcurementLocalStore.applyReceiptLocally(
        po: po,
        receiptId: 'create-receipt',
        receiptNo: 'GR-CREATE',
        userId: 'owner',
        inputs: const [
          GoodsReceiptItemInput(
            purchaseOrderItemId: 'po-item',
            receivedQuantity: 2,
            actualUnitCost: 5000,
          ),
        ],
      );

      final product = await LocalDatabase.select(
        'SELECT name, sale_price, cost_price FROM products WHERE id = ?',
        ['created-panel'],
      );
      final stock = await LocalDatabase.select(
        'SELECT quantity FROM inventory WHERE product_id = ?',
        ['created-panel'],
      );
      expect(product.single['name'], 'OLED Panel');
      expect((product.single['sale_price'] as num).toDouble(), 8000);
      expect((product.single['cost_price'] as num).toDouble(), 5000);
      expect((stock.single['quantity'] as num).toInt(), 2);
      expect(
        await ProcurementLocalStore.calculateSupplierPayable(_supplierId),
        10000,
      );
    },
  );

  test('unresolved receipt rolls back receipt and payable', () async {
    final po = _purchaseOrder(
      productId: null,
      resolution: PurchaseProductResolution.resolveOnReceipt,
    );
    await ProcurementLocalStore.savePurchaseOrder(po);

    await expectLater(
      ProcurementLocalStore.applyReceiptLocally(
        po: po,
        receiptId: 'unresolved-receipt',
        receiptNo: 'GR-UNRESOLVED',
        userId: 'owner',
        inputs: const [
          GoodsReceiptItemInput(
            purchaseOrderItemId: 'po-item',
            receivedQuantity: 1,
            actualUnitCost: 5000,
          ),
        ],
      ),
      throwsStateError,
    );
    expect(await LocalDatabase.select('SELECT * FROM goods_receipts'), isEmpty);
    expect(
      await LocalDatabase.select('SELECT * FROM supplier_ledger_entries'),
      isEmpty,
    );
    expect(
      await ProcurementLocalStore.calculateSupplierPayable(_supplierId),
      0,
    );
  });

  test('migration adds explicit resolution and immutable statement source', () {
    final sql =
        File(
          'supabase/migrations/20260728001300_supplier_ledger_product_resolution.sql',
        ).readAsStringSync().toLowerCase();
    expect(sql, contains('alter column product_id drop not null'));
    expect(sql, contains("'create_on_receipt'"));
    expect(sql, contains("'resolve_on_receipt'"));
    expect(sql, contains("'direct_use'"));
    expect(
      sql,
      contains('create table if not exists public.supplier_ledger_entries'),
    );
    expect(sql, contains("'supplier:receipt:' || new.id::text"));
    expect(sql, contains("'supplier:payment:' || new.id::text"));

    final executionSql =
        File(
          'supabase/migrations/20260728001400_procurement_product_resolution_execution.sql',
        ).readAsStringSync().toLowerCase();
    expect(executionSql, contains("v_resolution = 'direct_use'"));
    expect(executionSql, contains("v_resolution = 'create_on_receipt'"));
    expect(
      executionSql,
      contains("raise exception 'choose an inventory product before receipt.'"),
    );
    expect(executionSql, contains('insert into public.inventory'));
    expect(
      executionSql,
      contains('set outstanding_balance = outstanding_balance + v_total'),
    );
    expect(executionSql, isNot(contains('account_transactions')));
  });
}

PurchaseOrderModel _purchaseOrder({
  String? productId = _productId,
  PurchaseProductResolution resolution =
      PurchaseProductResolution.existingProduct,
  String? resolvedProductId,
  Map<String, dynamic>? productDraft,
}) {
  return PurchaseOrderModel(
    id: 'po-1',
    tenantId: _tenantId,
    branchId: _branchId,
    supplierId: _supplierId,
    poNo: 'PO-1',
    totalExpectedCost: 10000,
    createdBy: 'owner',
    createdAt: DateTime(2026, 7, 28),
    items: [
      PurchaseOrderItemModel(
        id: 'po-item',
        tenantId: _tenantId,
        purchaseOrderId: 'po-1',
        productId: productId,
        productResolution: resolution,
        resolvedProductId: resolvedProductId,
        productDraft: productDraft,
        productName: 'Panel',
        orderedQuantity: 2,
        negotiatedUnitCost: 5000,
        lineTotal: 10000,
      ),
    ],
  );
}
