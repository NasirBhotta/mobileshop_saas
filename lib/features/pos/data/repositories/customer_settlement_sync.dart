typedef SettlementLookup = Future<Map<String, dynamic>?> Function(String id);
typedef SettlementInsert = Future<void> Function(Map<String, dynamic> payload);
typedef SettlementCallback = Future<void> Function();
typedef SettlementMarkSynced = Future<void> Function(String id);

enum CustomerSettlementSyncResult { inserted, alreadyPresent }

class CustomerSettlementSyncConflict implements Exception {
  final String settlementId;

  const CustomerSettlementSyncConflict(this.settlementId);

  @override
  String toString() =>
      'CustomerSettlementSyncConflict(settlementId: $settlementId)';
}

class CustomerSettlementSyncService {
  final SettlementLookup findRemoteById;
  final SettlementInsert insertRemote;
  final SettlementCallback afterRemoteInsert;
  final SettlementMarkSynced markLocalSynced;

  const CustomerSettlementSyncService({
    required this.findRemoteById,
    required this.insertRemote,
    required this.afterRemoteInsert,
    required this.markLocalSynced,
  });

  Future<CustomerSettlementSyncResult> sync(
    Map<String, dynamic> payload,
  ) async {
    final settlementId = payload['id'] as String;
    final existing = await findRemoteById(settlementId);

    if (existing == null) {
      await insertRemote(payload);
      await afterRemoteInsert();
      await markLocalSynced(settlementId);
      return CustomerSettlementSyncResult.inserted;
    }

    if (!_isIdentical(existing, payload)) {
      throw CustomerSettlementSyncConflict(settlementId);
    }

    await markLocalSynced(settlementId);
    return CustomerSettlementSyncResult.alreadyPresent;
  }

  bool _isIdentical(
    Map<String, dynamic> existing,
    Map<String, dynamic> queued,
  ) {
    const stringFields = [
      'id',
      'customer_id',
      'branch_id',
      'user_id',
      'method',
      'notes',
    ];
    for (final field in stringFields) {
      if (existing[field] != queued[field]) return false;
    }

    final existingAmount = (existing['amount'] as num?)?.toDouble();
    final queuedAmount = (queued['amount'] as num?)?.toDouble();
    if (existingAmount != queuedAmount) return false;

    return _sameTimestamp(existing['created_at'], queued['created_at']);
  }

  bool _sameTimestamp(Object? first, Object? second) {
    if (first == second) return true;
    if (first is! String || second is! String) return false;
    final firstDate = _parseDatabaseTimestamp(first);
    final secondDate = _parseDatabaseTimestamp(second);
    if (firstDate == null || secondDate == null) return false;
    return firstDate.toUtc() == secondDate.toUtc();
  }

  DateTime? _parseDatabaseTimestamp(String value) {
    final hasTimeZone = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value);
    return DateTime.tryParse(hasTimeZone ? value : '${value}Z');
  }
}
