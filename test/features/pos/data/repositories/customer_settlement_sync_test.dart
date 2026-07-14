import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/data/repositories/customer_settlement_sync.dart';

void main() {
  const settlementId = 'settlement-1';
  final payload = <String, dynamic>{
    'id': settlementId,
    'customer_id': 'customer-1',
    'branch_id': 'branch-1',
    'user_id': 'user-1',
    'amount': 1250.0,
    'method': 'cash',
    'notes': null,
    'created_at': '2026-07-14T12:00:00.000Z',
  };

  test('absent settlement inserts and adjusts balance once', () async {
    var insertCount = 0;
    var balanceAdjustmentCount = 0;
    var markSyncedCount = 0;
    final service = CustomerSettlementSyncService(
      findRemoteById: (_) async => null,
      insertRemote: (inserted) async {
        expect(inserted, payload);
        insertCount++;
      },
      afterRemoteInsert: () async => balanceAdjustmentCount++,
      markLocalSynced: (id) async {
        expect(id, settlementId);
        markSyncedCount++;
      },
    );

    final result = await service.sync(payload);

    expect(result, CustomerSettlementSyncResult.inserted);
    expect(insertCount, 1);
    expect(balanceAdjustmentCount, 1);
    expect(markSyncedCount, 1);
  });

  test(
    'identical existing settlement succeeds without update or balance',
    () async {
      var insertCount = 0;
      var balanceAdjustmentCount = 0;
      var markSyncedCount = 0;
      final existing = Map<String, dynamic>.from(payload)
        ..['created_at'] = '2026-07-14T17:00:00.000+05:00';
      final service = CustomerSettlementSyncService(
        findRemoteById: (_) async => existing,
        insertRemote: (_) async => insertCount++,
        afterRemoteInsert: () async => balanceAdjustmentCount++,
        markLocalSynced: (_) async => markSyncedCount++,
      );

      final result = await service.sync(payload);

      expect(result, CustomerSettlementSyncResult.alreadyPresent);
      expect(insertCount, 0);
      expect(balanceAdjustmentCount, 0);
      expect(markSyncedCount, 1);
    },
  );

  test(
    'timezone-less queued timestamp matches database UTC timestamp',
    () async {
      var markSyncedCount = 0;
      final queued = Map<String, dynamic>.from(payload)
        ..['created_at'] = '2026-07-07T16:10:16.181498';
      final existing = Map<String, dynamic>.from(payload)
        ..['created_at'] = '2026-07-07T16:10:16.181498+00:00';
      final service = CustomerSettlementSyncService(
        findRemoteById: (_) async => existing,
        insertRemote:
            (_) async => fail('must not insert an existing settlement'),
        afterRemoteInsert: () async => fail('must not adjust balance'),
        markLocalSynced: (_) async => markSyncedCount++,
      );

      final result = await service.sync(queued);

      expect(result, CustomerSettlementSyncResult.alreadyPresent);
      expect(markSyncedCount, 1);
    },
  );

  test('conflicting settlement is not overwritten or marked synced', () async {
    var insertCount = 0;
    var balanceAdjustmentCount = 0;
    var markSyncedCount = 0;
    final existing = Map<String, dynamic>.from(payload)
      ..['branch_id'] = 'other';
    final service = CustomerSettlementSyncService(
      findRemoteById: (_) async => existing,
      insertRemote: (_) async => insertCount++,
      afterRemoteInsert: () async => balanceAdjustmentCount++,
      markLocalSynced: (_) async => markSyncedCount++,
    );

    await expectLater(
      service.sync(payload),
      throwsA(
        isA<CustomerSettlementSyncConflict>().having(
          (error) => error.settlementId,
          'settlementId',
          settlementId,
        ),
      ),
    );
    expect(insertCount, 0);
    expect(balanceAdjustmentCount, 0);
    expect(markSyncedCount, 0);
  });

  test('already present retry never adjusts customer balance twice', () async {
    var balanceAdjustmentCount = 0;
    final service = CustomerSettlementSyncService(
      findRemoteById: (_) async => payload,
      insertRemote: (_) async => fail('must not insert an existing settlement'),
      afterRemoteInsert: () async => balanceAdjustmentCount++,
      markLocalSynced: (_) async {},
    );

    await service.sync(payload);
    await service.sync(payload);

    expect(balanceAdjustmentCount, 0);
  });
}
