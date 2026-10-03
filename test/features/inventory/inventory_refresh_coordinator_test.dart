import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/inventory/data/sync/inventory_refresh_coordinator.dart';

void main() {
  test(
    'overlapping refreshes share one upload-before-download workflow',
    () async {
      final events = <String>[];
      final release = Completer<void>();
      final coordinator = InventoryRefreshCoordinator(
        upload: () async {
          events.add('upload');
          await release.future;
        },
        pullProducts: () async => events.add('products'),
        pullCategories: () async => events.add('categories'),
        pendingUploads: () async {
          events.add('pending');
          return 0;
        },
        uploadProblem: () => null,
      );
      final first = coordinator.refresh();
      final second = coordinator.refresh();
      expect(second, same(first));
      expect(events, ['upload']);
      release.complete();
      final result = await first;
      expect(events, ['upload', 'products', 'categories', 'pending']);
      expect(result.isComplete, isTrue);
      await coordinator.refresh();
      expect(events.where((event) => event == 'upload'), hasLength(2));
    },
  );

  test(
    'rejected uploads remain pending while remote reads can succeed',
    () async {
      final error = StateError('Upload rejected');
      final coordinator = InventoryRefreshCoordinator(
        upload: () async {},
        pullProducts: () async {},
        pullCategories: () async {},
        pendingUploads: () async => 28,
        uploadProblem: () => error,
      );
      final result = await coordinator.refresh();
      expect(result.pendingUploads, 28);
      expect(result.uploadError, same(error));
      expect(result.productsUpdated, isTrue);
      expect(result.isComplete, isFalse);
      expect(result.message, contains('28 inventory changes'));
    },
  );

  test('offline upload and download errors never report completion', () async {
    final coordinator = InventoryRefreshCoordinator(
      upload: () async => throw TimeoutException('Upload offline'),
      pullProducts: () async => throw TimeoutException('Download offline'),
      pullCategories: () async => throw TimeoutException('Download offline'),
      pendingUploads: () async => 1,
      uploadProblem: () => null,
    );
    final result = await coordinator.refresh();
    expect(result.pendingUploads, 1);
    expect(result.uploadError, isA<TimeoutException>());
    expect(result.productsUpdated, isFalse);
    expect(result.categoriesUpdated, isFalse);
    expect(result.isComplete, isFalse);
  });

  test('empty queue does not conceal an incomplete download', () async {
    final coordinator = InventoryRefreshCoordinator(
      upload: () async {},
      pullProducts: () async => throw StateError('Remote read failed'),
      pullCategories: () async {},
      pendingUploads: () async => 0,
      uploadProblem: () => null,
    );
    final result = await coordinator.refresh();
    expect(result.isComplete, isFalse);
    expect(result.message, contains('could not finish'));
  });
}
