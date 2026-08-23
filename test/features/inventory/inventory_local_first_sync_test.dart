import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/utils/offline_error_classifier.dart';
import 'package:mobileshop_saas/features/inventory/data/models/price_history_model.dart';
import 'package:mobileshop_saas/features/repairs/data/models/inventory_unit_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'inventory-local-first-',
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

  group('LocalStore Price History & Local IMEI Tests', () {
    test('saveProductPriceHistory and loadProductPriceHistory operate purely offline in SQLite', () async {
      const productId = 'prod-123';
      const tenantId = 'tenant-1';
      const branchId = 'branch-1';

      final historyItems = [
        PriceHistoryModel(
          id: 'ph-1',
          productId: productId,
          tenantId: tenantId,
          branchId: branchId,
          oldPrice: 1000.0,
          newPrice: 1200.0,
          changedBy: 'user-1',
          changedAt: DateTime(2026, 8, 20, 10, 0),
          changeSource: 'single_update',
        ),
        PriceHistoryModel(
          id: 'ph-2',
          productId: productId,
          tenantId: tenantId,
          branchId: branchId,
          oldPrice: 1200.0,
          newPrice: 1500.0,
          changedBy: 'user-1',
          changedAt: DateTime(2026, 8, 22, 14, 30),
          changeSource: 'single_update',
        ),
      ];

      await LocalStore.saveProductPriceHistory(historyItems);

      final loaded = await LocalStore.loadProductPriceHistory(productId);
      expect(loaded.length, 2);
      // Descending order by changed_at
      expect(loaded.first.id, 'ph-2');
      expect(loaded.first.newPrice, 1500.0);
      expect(loaded.last.id, 'ph-1');
      expect(loaded.last.oldPrice, 1000.0);
    });

    test('productHasActiveImeiUnits returns true when available unit exists in SQLite', () async {
      const productId = 'phone-xyz';
      const branchId = 'branch-1';

      // Initially false
      var hasActive = await LocalStore.productHasActiveImeiUnits(productId);
      expect(hasActive, isFalse);

      // Insert an available unit
      final unit = InventoryUnitModel(
        id: 'unit-1',
        tenantId: 'tenant-1',
        branchId: branchId,
        productId: productId,
        imei: '358291000000001',
        status: InventoryUnitStatus.available,
      );
      await LocalStore.upsertInventoryUnit(unit);

      hasActive = await LocalStore.productHasActiveImeiUnits(productId);
      expect(hasActive, isTrue);
    });

    test('loadStockAdjustments supports limit and ordering', () async {
      const branchId = 'branch-adjustments';
      const tenantId = 'tenant-1';
      const productId = 'product-adj';

      for (int i = 1; i <= 5; i++) {
        await LocalStore.saveStockAdjustment({
          'id': 'adj-$i',
          'tenant_id': tenantId,
          'branch_id': branchId,
          'product_id': productId,
          'adjustment_type': 'stock_in',
          'quantity': i * 10,
          'reason': 'Restock $i',
          'adjusted_by': 'user-1',
          'created_at': DateTime(2026, 8, i, 12, 0).toIso8601String(),
          'user_id': 'user-1',
          'reason_code': 'manual_restock',
          'reason_note': null,
          'is_override': 0,
          'unit_cost': 500.0,
          'total_value': (i * 10) * 500.0,
        });
      }

      final adjustments = await LocalStore.loadStockAdjustments(
        branchId,
        productId: productId,
        limit: 3,
      );

      expect(adjustments.length, 3);
      expect(adjustments.first['id'], 'adj-5');
    });
  });

  group('OfflineErrorClassifier Verification', () {
    test('classifies network timeouts and connection issues as retryable', () {
      expect(OfflineErrorClassifier.isRetryable(TimeoutException('Request timed out')), isTrue);
      expect(OfflineErrorClassifier.isRetryable(const SocketException('Failed host lookup')), isTrue);
    });

    test('classifies database schema / auth / postgrest errors as terminal', () {
      expect(
        OfflineErrorClassifier.isRetryable(
          const PostgrestException(message: 'duplicate key value violates unique constraint'),
        ),
        isFalse,
      );
      expect(
        OfflineErrorClassifier.isRetryable(
          const AuthException('Invalid JWT token'),
        ),
        isFalse,
      );
    });
  });
}
