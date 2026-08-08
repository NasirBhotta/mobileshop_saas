import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'inventory-supplier-offline-',
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
    if (databaseDirectory.existsSync()) {
      databaseDirectory.deleteSync(recursive: true);
    }
  });

  test('local supplier relation combines with search and category filters', () async {
    const tenantId = 'tenant';
    const branchId = 'branch';
    const supplierA = 'supplier-a';
    const supplierB = 'supplier-b';
    const categoryId = 'accessories';

    await LocalDatabase.execute(
      '''
      INSERT INTO categories(
        id, tenant_id, branch_id, name, default_reorder_threshold
      ) VALUES(?, ?, ?, 'Accessories', 1)
      ''',
      [categoryId, tenantId, branchId],
    );
    for (final product in const [
      ProductModel(
        id: 'keypad',
        tenantId: tenantId,
        branchId: branchId,
        categoryId: categoryId,
        name: 'Keypad G1',
        salePrice: 500,
        costPrice: 250,
        stock: 9,
      ),
      ProductModel(
        id: 'charger',
        tenantId: tenantId,
        branchId: branchId,
        categoryId: categoryId,
        name: 'Fast Charger',
        salePrice: 1000,
        costPrice: 700,
        stock: 4,
      ),
    ]) {
      await LocalStore.upsertProduct(product);
    }
    await LocalStore.saveSupplierProductLinks(
      tenantId: tenantId,
      supplierId: supplierA,
      links: const [
        {'id': 'a-keypad', 'product_id': 'keypad'},
      ],
    );
    await LocalStore.saveSupplierProductLinks(
      tenantId: tenantId,
      supplierId: supplierB,
      links: const [
        {'id': 'b-charger', 'product_id': 'charger'},
      ],
    );

    final results = await LocalStore.searchProducts(
      branchId: branchId,
      supplierId: supplierA,
      categoryId: categoryId,
      query: 'key',
    );

    expect(results.map((product) => product.id), ['keypad']);
  });
}
