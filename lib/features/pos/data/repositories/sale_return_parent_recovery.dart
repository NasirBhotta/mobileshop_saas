typedef RemoteSaleLookup = Future<bool> Function(String saleId);
typedef LocalSaleSnapshotLoader =
    Future<Map<String, dynamic>?> Function(String saleId);
typedef RemoteSaleRestore =
    Future<void> Function(Map<String, dynamic> snapshot);

class MissingSaleReturnParent implements Exception {
  final String saleId;

  const MissingSaleReturnParent(this.saleId);

  @override
  String toString() => 'MissingSaleReturnParent(saleId: $saleId)';
}

class SaleReturnParentRecoveryService {
  final RemoteSaleLookup remoteSaleExists;
  final LocalSaleSnapshotLoader loadLocalSnapshot;
  final RemoteSaleRestore restoreRemoteSale;

  const SaleReturnParentRecoveryService({
    required this.remoteSaleExists,
    required this.loadLocalSnapshot,
    required this.restoreRemoteSale,
  });

  Future<void> ensureRemoteParent(String saleId) async {
    if (await remoteSaleExists(saleId)) return;

    final snapshot = await loadLocalSnapshot(saleId);
    if (snapshot == null) throw MissingSaleReturnParent(saleId);

    await restoreRemoteSale(snapshot);
  }
}
