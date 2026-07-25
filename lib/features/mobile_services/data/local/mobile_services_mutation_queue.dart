import 'package:mobileshop_saas/core/offline/offline_store.dart';

abstract interface class MobileServicesMutationQueue {
  Future<void> enqueue({
    required String userId,
    required String type,
    required Map<String, dynamic> payload,
  });

  Future<List<OfflineMutation>> load(String userId);

  Future<void> saveSyncResult({
    required String userId,
    required List<OfflineMutation> snapshot,
    required List<OfflineMutation> remaining,
  });
}

class OfflineStoreMobileServicesMutationQueue
    implements MobileServicesMutationQueue {
  const OfflineStoreMobileServicesMutationQueue();

  @override
  Future<void> enqueue({
    required String userId,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    return OfflineStore.enqueueMutation(
      userId: userId,
      type: type,
      payload: payload,
    );
  }

  @override
  Future<List<OfflineMutation>> load(String userId) {
    return OfflineStore.loadMutations(userId);
  }

  @override
  Future<void> saveSyncResult({
    required String userId,
    required List<OfflineMutation> snapshot,
    required List<OfflineMutation> remaining,
  }) {
    return OfflineStore.saveMutationSyncResult(
      userId: userId,
      snapshot: snapshot,
      remaining: remaining,
    );
  }
}
