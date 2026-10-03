class InventoryRefreshResult {
  final int pendingUploads;
  final bool productsUpdated;
  final bool categoriesUpdated;
  final Object? uploadError;

  const InventoryRefreshResult({
    required this.pendingUploads,
    required this.productsUpdated,
    required this.categoriesUpdated,
    this.uploadError,
  });

  bool get isComplete =>
      pendingUploads == 0 &&
      uploadError == null &&
      productsUpdated &&
      categoriesUpdated;

  String get message {
    if (pendingUploads > 0) {
      return '$pendingUploads inventory changes are still pending upload. '
          'Your changes remain saved on this device.';
    }
    if (!productsUpdated || !categoriesUpdated || uploadError != null) {
      return 'Inventory refresh could not finish. Local data has been kept; retry when online.';
    }
    return 'Inventory synced and refreshed';
  }
}

/// One upload-then-download workflow shared by every manual refresh caller.
/// Transport/cache failures retain local data and are reported separately.
class InventoryRefreshCoordinator {
  final Future<void> Function() upload;
  final Future<void> Function() pullProducts;
  final Future<void> Function() pullCategories;
  final Future<int> Function() pendingUploads;
  final Object? Function() uploadProblem;
  Future<InventoryRefreshResult>? _inFlight;

  InventoryRefreshCoordinator({
    required this.upload,
    required this.pullProducts,
    required this.pullCategories,
    required this.pendingUploads,
    required this.uploadProblem,
  });

  Future<InventoryRefreshResult> refresh() {
    final active = _inFlight;
    if (active != null) return active;
    late final Future<InventoryRefreshResult> refresh;
    refresh = _refresh().whenComplete(() {
      if (identical(_inFlight, refresh)) _inFlight = null;
    });
    _inFlight = refresh;
    return refresh;
  }

  Future<InventoryRefreshResult> _refresh() async {
    Object? failure;
    try {
      await upload();
      failure = uploadProblem();
    } catch (error) {
      failure = error;
    }
    final updated = await Future.wait([
      _pull(pullProducts),
      _pull(pullCategories),
    ]);
    return InventoryRefreshResult(
      pendingUploads: await pendingUploads(),
      productsUpdated: updated[0],
      categoriesUpdated: updated[1],
      uploadError: failure,
    );
  }

  Future<bool> _pull(Future<void> Function() pull) async {
    try {
      await pull();
      return true;
    } catch (_) {
      return false;
    }
  }
}
