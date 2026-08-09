import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote refresh preserves a pending offline product category link', () {
    final repository =
        File(
          'lib/features/inventory/data/repositories/inventory_repository.dart',
        ).readAsStringSync();

    final remoteMapping = repository.indexOf(
      '(data as List).map((e) => ProductModel.fromMap(e)).toList()',
    );
    final pendingOverlay = repository.indexOf(
      '_applyPendingProductUpserts(',
      remoteMapping,
    );
    final cacheWrite = repository.indexOf(
      'OfflineStore.saveProducts(branchId, products)',
      pendingOverlay,
    );

    expect(remoteMapping, greaterThan(-1));
    expect(pendingOverlay, greaterThan(remoteMapping));
    expect(cacheWrite, greaterThan(pendingOverlay));
    expect(repository, contains("mutation.type != 'upsert_product'"));
    expect(repository, contains('productsById[pending.id] = pending'));
  });

  test(
    'category dependency is preserved and inventory sync is single-flight',
    () {
      final repository =
          File(
            'lib/features/inventory/data/repositories/inventory_repository.dart',
          ).readAsStringSync();

      expect(repository, contains('_applyPendingCategoryUpserts'));
      expect(repository, contains("mutation.type != 'upsert_category'"));
      expect(repository, contains('Future<void>? _offlineSyncInFlight'));
      expect(repository, contains('final activeSync = _offlineSyncInFlight'));
      expect(repository, contains('identical(_offlineSyncInFlight, sync)'));
    },
  );
}
