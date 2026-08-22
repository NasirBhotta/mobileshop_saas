import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/buyin/data/models/customer_purchase_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Customer Purchases Offline Store & Model Integration', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves and retrieves customer purchase list in offline cache', () async {
      const branchId = 'test-branch-1';
      final now = DateTime.now();

      final purchase1 = CustomerPurchaseModel(
        id: 'purchase-1',
        tenantId: 'tenant-1',
        branchId: branchId,
        sellerName: 'Zubair Tariq',
        sellerCnic: '35201-1112223-3',
        sellerPhone: '0321-9988776',
        productId: 'prod-oneplus-11',
        productName: 'OnePlus 11 5G',
        imei1: '869234051111111',
        purchasePrice: 95000.0,
        expectedSalePrice: 108000.0,
        declarationAgreed: true,
        status: 'in_stock',
        createdBy: 'user-1',
        createdAt: now,
        updatedAt: now,
      );

      final purchase2 = CustomerPurchaseModel(
        id: 'purchase-2',
        tenantId: 'tenant-1',
        branchId: branchId,
        sellerName: 'Usman Ali',
        sellerCnic: '35201-4445556-7',
        sellerPhone: '0333-1122334',
        productId: 'prod-xiaomi-13',
        productName: 'Xiaomi 13 Pro',
        imei1: '869234052222222',
        purchasePrice: 110000.0,
        expectedSalePrice: 125000.0,
        declarationAgreed: true,
        status: 'in_stock',
        createdBy: 'user-1',
        createdAt: now.add(const Duration(minutes: 10)),
        updatedAt: now.add(const Duration(minutes: 10)),
      );

      // Save initial list
      await OfflineStore.saveCustomerPurchases(branchId, [purchase1, purchase2]);

      // Load all
      final all = await OfflineStore.loadCustomerPurchases(branchId);
      expect(all.length, 2);

      // Search by IMEI
      final imeiSearch = await OfflineStore.loadCustomerPurchases(
        branchId,
        query: '869234051111111',
      );
      expect(imeiSearch.length, 1);
      expect(imeiSearch.first.sellerName, 'Zubair Tariq');

      // Search by CNIC
      final cnicSearch = await OfflineStore.loadCustomerPurchases(
        branchId,
        query: '4445556',
      );
      expect(cnicSearch.length, 1);
      expect(cnicSearch.first.productName, 'Xiaomi 13 Pro');

      // Save single new purchase
      final purchase3 = CustomerPurchaseModel(
        id: 'purchase-3',
        tenantId: 'tenant-1',
        branchId: branchId,
        sellerName: 'Bilal Ahmed',
        sellerCnic: '35201-7778889-9',
        sellerPhone: '0345-5566778',
        productId: 'prod-pixel-8',
        productName: 'Google Pixel 8',
        imei1: '869234053333333',
        purchasePrice: 120000.0,
        expectedSalePrice: 135000.0,
        declarationAgreed: true,
        status: 'in_stock',
        createdBy: 'user-1',
        createdAt: now.add(const Duration(minutes: 20)),
        updatedAt: now.add(const Duration(minutes: 20)),
      );

      await OfflineStore.saveCustomerPurchase(purchase3);

      final updatedList = await OfflineStore.loadCustomerPurchases(branchId);
      expect(updatedList.length, 3);

      // Delete purchase
      await OfflineStore.deleteCustomerPurchase(branchId, 'purchase-2');
      final afterDelete = await OfflineStore.loadCustomerPurchases(branchId);
      expect(afterDelete.length, 2);
      expect(afterDelete.any((p) => p.id == 'purchase-2'), false);

      // Mark purchase sold via POS checkout simulation
      final soldUnits = await OfflineStore.markCustomerPurchasesSold(
        branchId: branchId,
        productId: 'prod-oneplus-11',
        quantity: 1,
      );
      expect(soldUnits.length, 1);
      expect(soldUnits.first.id, 'purchase-1');
      expect(soldUnits.first.status, 'sold');

      final finalPurchases = await OfflineStore.loadCustomerPurchases(branchId);
      final p1 = finalPurchases.firstWhere((p) => p.id == 'purchase-1');
      expect(p1.status, 'sold');
    });
  });
}
