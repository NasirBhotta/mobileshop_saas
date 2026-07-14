import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/data/repositories/sale_return_parent_recovery.dart';

void main() {
  test('existing remote parent does not restore local snapshot', () async {
    var loadCount = 0;
    var restoreCount = 0;
    final service = SaleReturnParentRecoveryService(
      remoteSaleExists: (_) async => true,
      loadLocalSnapshot: (_) async {
        loadCount++;
        return {};
      },
      restoreRemoteSale: (_) async => restoreCount++,
    );

    await service.ensureRemoteParent('sale-1');

    expect(loadCount, 0);
    expect(restoreCount, 0);
  });

  test('missing remote parent restores complete local snapshot', () async {
    var restoreCount = 0;
    final snapshot = <String, dynamic>{
      'sale': {'id': 'sale-1'},
      'items': [
        {'id': 'item-1'},
      ],
      'payments': [
        {'id': 'payment-1'},
      ],
    };
    final service = SaleReturnParentRecoveryService(
      remoteSaleExists: (_) async => false,
      loadLocalSnapshot: (_) async => snapshot,
      restoreRemoteSale: (restored) async {
        expect(restored, snapshot);
        restoreCount++;
      },
    );

    await service.ensureRemoteParent('sale-1');

    expect(restoreCount, 1);
  });

  test('missing remote and local parent throws typed failure', () async {
    final service = SaleReturnParentRecoveryService(
      remoteSaleExists: (_) async => false,
      loadLocalSnapshot: (_) async => null,
      restoreRemoteSale: (_) async => fail('must not restore missing data'),
    );

    await expectLater(
      service.ensureRemoteParent('sale-1'),
      throwsA(
        isA<MissingSaleReturnParent>().having(
          (error) => error.saleId,
          'saleId',
          'sale-1',
        ),
      ),
    );
  });
}
