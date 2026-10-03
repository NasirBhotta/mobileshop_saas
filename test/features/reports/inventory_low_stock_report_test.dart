import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/reports/data/local/business_report_local_store.dart';
import 'package:mobileshop_saas/features/reports/data/models/business_report_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    final directory = Directory.systemTemp.createTempSync('inventory-report-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => directory.path);
    await LocalDatabase.initialize();
  });
  setUp(() async {
    for (final table in [
      'business_report_cache',
      'inventory',
      'products',
      'categories',
    ]) {
      await LocalDatabase.clearTable(table);
    }
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> product(
    String id, {
    int quantity = 1,
    int branchThreshold = 0,
    int productThreshold = 0,
    int categoryThreshold = 0,
    bool active = true,
    String tenant = 'tenant',
    String branch = 'branch',
    bool inventory = true,
  }) async {
    await LocalDatabase.execute(
      'INSERT INTO categories(id, tenant_id, branch_id, name, default_reorder_threshold) VALUES(?, ?, ?, ?, ?)',
      ['category-$id', tenant, branch, 'Category', categoryThreshold],
    );
    await LocalDatabase.execute(
      'INSERT INTO products(id, tenant_id, branch_id, category_id, name, reorder_threshold, is_active, cost_price) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        tenant,
        branch,
        'category-$id',
        id,
        productThreshold,
        active ? 1 : 0,
        10,
      ],
    );
    if (inventory) {
      await LocalDatabase.execute(
        'INSERT INTO inventory(id, product_id, branch_id, quantity, reorder_threshold) VALUES(?, ?, ?, ?, ?)',
        ['inventory-$id', id, branch, quantity, branchThreshold],
      );
    }
  }

  Future<Map<String, dynamic>> report() =>
      BusinessReportLocalStore.buildLocalReport(
        reportType: BusinessReportType.inventory,
        tenantId: 'tenant',
        branchId: 'branch',
        dateFrom: DateTime(2026, 10, 3),
        dateTo: DateTime(2026, 10, 3),
      );

  test(
    'report counts 139 low-stock items without the nine above their product threshold',
    () async {
      for (var i = 0; i < 139; i++) {
        await product('low-$i', quantity: 2, productThreshold: 2);
      }
      for (var i = 0; i < 9; i++) {
        await product('healthy-$i', quantity: 3, productThreshold: 2);
      }
      await product('zero', quantity: 0, productThreshold: 2);
      final data = await report();
      final summary = data['summary'] as Map;
      expect(summary['low_stock_count'], 139);
      expect(summary['out_of_stock_count'], 1);
      expect(summary['total_products'], 149);
      expect(summary['total_stock'], 305);
      expect(summary['stock_value'], 3050);
      expect(
        (data['low_stock'] as List).map((item) => item['product_id']),
        unorderedEquals([for (var i = 0; i < 139; i++) 'low-$i']),
      );
    },
  );

  test(
    'threshold precedence and report scope match the catalog rules',
    () async {
      await product(
        'branch-wins',
        quantity: 3,
        branchThreshold: 2,
        productThreshold: 9,
        categoryThreshold: 10,
      );
      await product(
        'branch-low',
        quantity: 3,
        branchThreshold: 3,
        productThreshold: 1,
      );
      await product(
        'product-wins',
        quantity: 3,
        productThreshold: 2,
        categoryThreshold: 10,
      );
      await product('category-wins', quantity: 3, categoryThreshold: 2);
      await product('category-low', quantity: 2, categoryThreshold: 2);
      await product('default-low', quantity: 5);
      await product('default-healthy', quantity: 6);
      await product('zero', quantity: 0);
      await product('missing-inventory', inventory: false);
      await product('inactive', active: false);
      await product('other-tenant', tenant: 'other');
      await product('other-branch', branch: 'other');
      final data = await report();
      expect(
        (data['low_stock'] as List).map((item) => item['product_id']),
        unorderedEquals(['branch-low', 'category-low', 'default-low']),
      );
      expect((data['summary'] as Map)['out_of_stock_count'], 2);
    },
  );
}
