import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/buyin/data/models/customer_purchase_model.dart';

void main() {
  group('CustomerPurchaseModel', () {
    test('serializes to map and deserializes correctly', () {
      final now = DateTime.now();
      final model = CustomerPurchaseModel(
        id: 'buyin-123',
        tenantId: 'tenant-abc',
        branchId: 'branch-xyz',
        sellerName: 'Muhammad Ali',
        sellerCnic: '35201-1234567-1',
        sellerPhone: '03001234567',
        sellerAddress: 'Model Town, Lahore',
        productId: 'prod-456',
        productName: 'iPhone 13 Pro Max',
        categoryId: 'cat-mobiles',
        imei1: '354890123456789',
        imei2: '354890123456790',
        color: 'Sierra Blue',
        storage: '256 GB',
        deviceCondition: '10/10 (Mint)',
        accessories: 'Original Box, Charger',
        purchasePrice: 165000.0,
        expectedSalePrice: 185000.0,
        paymentAccountId: 'acc-cash-drawer',
        paymentMethod: 'cash',
        notes: 'Clean device, battery health 89%',
        declarationAgreed: true,
        status: 'in_stock',
        createdBy: 'user-001',
        createdAt: now,
        updatedAt: now,
      );

      final map = model.toMap();
      expect(map['id'], 'buyin-123');
      expect(map['seller_name'], 'Muhammad Ali');
      expect(map['seller_cnic'], '35201-1234567-1');
      expect(map['imei1'], '354890123456789');
      expect(map['purchase_price'], 165000.0);
      expect(map['declaration_agreed'], 1);

      final fromMap = CustomerPurchaseModel.fromMap(map);
      expect(fromMap.id, model.id);
      expect(fromMap.sellerName, model.sellerName);
      expect(fromMap.sellerCnic, model.sellerCnic);
      expect(fromMap.imei1, model.imei1);
      expect(fromMap.purchasePrice, model.purchasePrice);
      expect(fromMap.declarationAgreed, true);
    });

    test('copyWith updates specified fields only', () {
      final now = DateTime.now();
      final model = CustomerPurchaseModel(
        id: 'buyin-123',
        tenantId: 'tenant-abc',
        branchId: 'branch-xyz',
        sellerName: 'Muhammad Ali',
        sellerCnic: '35201-1234567-1',
        sellerPhone: '03001234567',
        productId: 'prod-456',
        productName: 'iPhone 13 Pro Max',
        imei1: '354890123456789',
        purchasePrice: 165000.0,
        expectedSalePrice: 185000.0,
        createdBy: 'user-001',
        createdAt: now,
        updatedAt: now,
      );

      final updated = model.copyWith(
        status: 'sold',
        expectedSalePrice: 190000.0,
      );

      expect(updated.id, 'buyin-123');
      expect(updated.status, 'sold');
      expect(updated.expectedSalePrice, 190000.0);
      expect(updated.purchasePrice, 165000.0);
    });
  });
}
