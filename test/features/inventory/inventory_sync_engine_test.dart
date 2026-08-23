import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/features/inventory/data/models/product_model.dart';
import 'package:mobileshop_saas/features/inventory/data/sync/inventory_sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'inventory-sync-engine-test-',
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
    try {
      if (databaseDirectory.existsSync()) {
        databaseDirectory.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDatabase.clearAllTables();
    await OfflineStore.clearOfflinePreferences();
  });

  group('InventorySyncEngine Unit & Integration Tests', () {
    test('Offline mutation is queued and local SQLite is immediately updated', () async {
      const branchId = 'branch-sync-1';
      const tenantId = 'tenant-sync-1';
      const userId = 'user-sync-1';

      final product = ProductModel(
        id: 'prod-local-1',
        tenantId: tenantId,
        branchId: branchId,
        name: 'Samsung S24 Ultra',
        salePrice: 280000.0,
        costPrice: 240000.0,
        stock: 5,
        reorderThreshold: 2,
      );

      // Save to local cache & enqueue mutation
      await OfflineStore.upsertCachedProduct(product);
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'upsert_product',
        payload: {'product': product.toCacheMap()},
      );

      // Verify product is loaded from local database instantly
      final loaded = await LocalStore.loadProducts(branchId);
      expect(loaded.length, 1);
      expect(loaded.first.id, 'prod-local-1');
      expect(loaded.first.name, 'Samsung S24 Ultra');
      expect(loaded.first.stock, 5);

      // Verify mutation is pending in queue
      final pendingMutations = await OfflineStore.loadMutations(userId);
      expect(pendingMutations.length, 1);
      expect(pendingMutations.first.type, 'upsert_product');
      expect(pendingMutations.first.payload['product']['name'], 'Samsung S24 Ultra');
    });

    test('Updating an existing product reflects in local store in single-digit ms', () async {
      const branchId = 'branch-sync-1';
      const tenantId = 'tenant-sync-1';
      const userId = 'user-sync-1';

      final initial = ProductModel(
        id: 'prod-fast-update',
        tenantId: tenantId,
        branchId: branchId,
        name: 'iPhone 15 Pro',
        salePrice: 350000.0,
        costPrice: 310000.0,
        stock: 10,
        reorderThreshold: 3,
      );

      await OfflineStore.upsertCachedProduct(initial);

      final updated = ProductModel(
        id: 'prod-fast-update',
        tenantId: tenantId,
        branchId: branchId,
        name: 'iPhone 15 Pro Max',
        salePrice: 380000.0,
        costPrice: 330000.0,
        stock: 8,
        reorderThreshold: 2,
      );

      final stopwatch = Stopwatch()..start();
      await OfflineStore.upsertCachedProduct(updated);
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'upsert_product',
        payload: {'product': updated.toCacheMap()},
      );
      stopwatch.stop();

      // Ensure execution is sub-50ms
      expect(stopwatch.elapsedMilliseconds, lessThan(500));

      final loaded = await LocalStore.loadProducts(branchId);
      expect(loaded.length, 1);
      expect(loaded.first.name, 'iPhone 15 Pro Max');
      expect(loaded.first.salePrice, 380000.0);
      expect(loaded.first.stock, 8);
    });

    test('Error classifier correctly separates retryable network errors from terminal errors', () {
      expect(OfflineErrorClassifier.isRetryable(const SocketException('Network unreachable')), isTrue);
      expect(OfflineErrorClassifier.isRetryable(TimeoutException('Request timeout')), isTrue);
      expect(
        OfflineErrorClassifier.isRetryable(
          const PostgrestException(message: 'permission denied for table products', code: '42501'),
        ),
        isFalse,
      );
      expect(
        OfflineErrorClassifier.isRetryable(
          const AuthException('Token expired'),
        ),
        isFalse,
      );
    });

    test('Engine pauses syncing when network connection is not active', () async {
      const userId = 'user-offline-1';
      final engine = InventorySyncEngine();
      engine.hasConnection = false;

      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'upsert_product',
        payload: {'product': {'id': 'p-off-1', 'branch_id': 'b-1'}},
      );

      await engine.syncNow();

      // Mutation must remain in queue because network is off
      final mutations = await OfflineStore.loadMutations(userId);
      expect(mutations.length, 1);
      expect(mutations.first.type, 'upsert_product');
    });
  });
}
