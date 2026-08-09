import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/suppliers/data/local/procurement_local_store.dart';
import 'package:mobileshop_saas/features/suppliers/data/models/supplier_sales_analytics_models.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'supplier-analytics-offline-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return databaseDirectory.path;
          }
          return null;
        });
    await LocalDatabase.initialize();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    // LocalDatabase owns one process-wide lazy connection. Windows can keep
    // the temporary SQLite file locked until the test isolate exits.
    try {
      if (databaseDirectory.existsSync()) {
        databaseDirectory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // The OS releases and cleans the temporary test directory afterwards.
    }
  });

  test(
    'local analytics preserves shared-product and approved-return rules',
    () async {
      await LocalDatabase.execute(
        "INSERT INTO products(id, tenant_id, branch_id, name, sku) VALUES"
        "('p1', 't1', 'b1', 'Charger', 'CH-1')",
      );
      await LocalDatabase.execute(
        "INSERT INTO inventory(id, branch_id, product_id, quantity) VALUES"
        "('i1', 'b1', 'p1', 7)",
      );
      await LocalDatabase.execute(
        "INSERT INTO supplier_products(id, tenant_id, supplier_id, product_id) "
        "VALUES('sp1', 't1', 'supplier-1', 'p1')",
      );
      await LocalDatabase.execute(
        "INSERT INTO sales(id, branch_id, user_id, status, created_at) VALUES"
        "('sale-1', 'b1', 'u1', 'completed', '2026-08-01T00:00:00Z')",
      );
      await LocalDatabase.execute(
        "INSERT INTO sale_items(id, sale_id, product_id, product_name, quantity, "
        "unit_price, cogs_total, line_total) VALUES"
        "('line-1', 'sale-1', 'p1', 'Charger', 2, 100, 120, 200)",
      );
      await LocalDatabase.execute(
        "INSERT INTO sale_returns(id, original_sale_id, branch_id, user_id, status, "
        "refund_method, created_at) VALUES"
        "('return-1', 'sale-1', 'b1', 'u1', 'approved', 'cash', "
        "'2026-08-02T00:00:00Z')",
      );
      await LocalDatabase.execute(
        "INSERT INTO sale_return_items(id, return_id, original_sale_id, product_id, "
        "product_name, quantity, refund_amount) VALUES"
        "('return-line-1', 'return-1', 'sale-1', 'p1', 'Charger', 1, 100)",
      );

      final summary = await ProcurementLocalStore.loadSupplierSalesSummary(
        supplierId: 'supplier-1',
        branchId: 'b1',
        dateFrom: null,
      );
      final page = await ProcurementLocalStore.loadSupplierProductSalesPage(
        supplierId: 'supplier-1',
        branchId: 'b1',
        dateFrom: null,
        search: 'charge',
        profitFilter: SupplierProfitFilter.all,
        sort: SupplierAnalyticsSort.revenue,
        limit: 50,
        offset: 0,
      );

      expect(summary.linkedProductCount, 1);
      expect(summary.unitsSold, 1);
      expect(summary.revenue, 100);
      expect(summary.costOfSales, 60);
      expect(page.total, 1);
      expect(page.items.single.stock, 7);
      expect(page.items.single.grossProfit, 40);
    },
  );
}
