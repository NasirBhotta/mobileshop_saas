import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/data/repositories/inventory_repository.dart';
import 'package:mobileshop_saas/features/inventory/data/sync/inventory_sync_engine.dart';
import 'package:mobileshop_saas/features/onboarding/data/models/shop_setup_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const userId = 'refresh-user';
  const branchId = 'refresh-branch';
  const tenantId = 'refresh-tenant';
  late Directory directory;
  late HttpServer server;
  late SupabaseClient client;
  late InventorySyncEngine engine;
  late InventoryRepository repository;
  late List<Map<String, dynamic>> remote;
  late List<int> offsets;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('inventory-refresh-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => directory.path);
    await LocalDatabase.initialize();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> remoteProduct(String id) => {
    'id': id,
    'tenant_id': tenantId,
    'branch_id': branchId,
    'name': id,
    'sale_price': 100.0,
    'cost_price': 50.0,
    'is_active': true,
    'inventory': [
      {'quantity': 2, 'branch_id': branchId},
    ],
  };

  setUp(() async {
    await LocalDatabase.clearAllTables();
    SharedPreferences.setMockInitialValues({});
    remote = [];
    offsets = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method != 'GET') {
        request.response.statusCode = 403;
        request.response.write(
          jsonEncode({'code': '42501', 'message': 'Blocked test upload'}),
        );
      } else if (request.uri.path.endsWith('/users')) {
        request.response.write(
          jsonEncode({
            'id': userId,
            'tenant_id': tenantId,
            'branch_id': branchId,
          }),
        );
      } else if (request.uri.path.endsWith('/products')) {
        final offset =
            int.tryParse(request.uri.queryParameters['offset'] ?? '') ?? 0;
        final limit =
            int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 200;
        offsets.add(offset);
        request.response.write(
          jsonEncode(remote.skip(offset).take(limit).toList()),
        );
      } else {
        request.response.write('[]');
      }
      await request.response.close();
    });
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'test-key');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-session',
        'token_type': 'bearer',
        'user': {
          'id': userId,
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    await OfflineStore.saveProfile(userId, {
      'tenant_id': tenantId,
      'branch_id': branchId,
    });
    await OfflineStore.saveBranches(tenantId, const [
      BranchInputModel(id: branchId),
    ]);
    engine = InventorySyncEngine(client: client);
    engine.hasConnection = true;
    repository = InventoryRepository(client: client, syncEngine: engine);
  });
  tearDown(() async {
    engine.dispose();
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'full refresh downloads all pages before updating local cache',
    () async {
      remote = List.generate(205, (index) => remoteProduct('product-$index'));
      final result = await repository.refreshInventory();
      expect(result.isComplete, isTrue);
      expect(offsets, [0, 200]);
      final local = await LocalStore.loadProducts(branchId);
      expect(local, hasLength(205));
      expect(
        local.fold<double>(
          0,
          (sum, product) => sum + product.costPrice * product.stock,
        ),
        205 * 50 * 2,
      );
    },
  );

  test(
    'refresh preserves distinct barcoded products with the same SKU',
    () async {
      remote = [
        {
          ...remoteProduct('pixel-6-pro'),
          'name': 'GOOGLE PIXEL 6 PRO',
          'sku': '12/128 Official PTA',
          'barcode': '2090282967632',
          'cost_price': 63000.0,
          'sale_price': 78000.0,
        },
        {
          ...remoteProduct('pixel-7-pro'),
          'name': 'GOOGLE PIXEL 7 PRO',
          'sku': '12/128 Official PTA',
          'barcode': '2090277682366',
          'cost_price': 79000.0,
          'sale_price': 94000.0,
        },
      ];
      final result = await repository.refreshInventory();
      expect(result.isComplete, isTrue);
      final local = await LocalStore.loadProducts(branchId);
      expect(local, hasLength(2));
      for (final row in remote) {
        final product = local.singleWhere((p) => p.id == row['id']);
        expect(product.toCacheMap(), ProductModel.fromMap(row).toCacheMap());
      }
      expect(
        local.fold<double>(0, (sum, p) => sum + p.costPrice * p.stock),
        (63000 + 79000) * 2,
      );
    },
  );

  test(
    'failed stock upload cannot be overwritten by stale remote stock/prices',
    () async {
      const product = ProductModel(
        id: 'phone',
        tenantId: tenantId,
        branchId: branchId,
        name: 'Phone',
        salePrice: 456.78,
        costPrice: 123.45,
        stock: 7,
      );
      await OfflineStore.upsertCachedProduct(product);
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'stock_adjustment',
        payload: {
          'adjustment': {
            'id': 'adjustment',
            'product_id': 'phone',
            'tenant_id': tenantId,
            'branch_id': branchId,
          },
          'new_stock': 7,
        },
      );
      final before = await OfflineStore.loadMutations(userId);
      remote = [remoteProduct('phone')];
      final result = await repository.refreshInventory();
      expect(result.isComplete, isFalse);
      expect(result.pendingUploads, 1);
      final after = (await LocalStore.loadProducts(branchId)).single;
      expect(after.toCacheMap(), product.toCacheMap());
      expect(
        (await OfflineStore.loadMutations(userId)).map((m) => m.toMap()),
        before.map((m) => m.toMap()),
      );
    },
  );

  test('pending deletion is not resurrected by remote refresh', () async {
    final product = ProductModel.fromMap(remoteProduct('deleted'));
    await OfflineStore.upsertCachedProduct(product);
    await OfflineStore.deactivateCachedProduct(
      branchId: branchId,
      productId: product.id,
    );
    await OfflineStore.enqueueMutation(
      userId: userId,
      type: 'delete_product',
      payload: {
        'product_id': product.id,
        'tenant_id': tenantId,
        'branch_id': branchId,
      },
    );
    remote = [remoteProduct('deleted')];
    final result = await repository.refreshInventory();
    expect(result.pendingUploads, 1);
    expect(await LocalStore.loadProducts(branchId), isEmpty);
    expect(
      (await LocalDatabase.select(
        'SELECT is_active FROM products WHERE id = ?',
        ['deleted'],
      )).single['is_active'],
      0,
    );
  });
}
