import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/buyin/data/models/customer_purchase_model.dart';
import 'package:mobileshop_saas/features/buyin/data/services/buyin_thermal_receipt_service.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BuyInThermalReceiptService', () {
    final testPurchase = CustomerPurchaseModel(
      id: 'buyin-test-1',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      sellerName: 'Hamza Khan',
      sellerCnic: '35202-9876543-1',
      sellerPhone: '0312-3456789',
      sellerAddress: 'Gulberg III, Lahore',
      productId: 'prod-samsung-22',
      productName: 'Samsung Galaxy S22 Ultra 256GB',
      imei1: '869234051234567',
      imei2: '869234051234568',
      color: 'Phantom Black',
      storage: '256 GB',
      deviceCondition: '9/10 (Minor Scratches)',
      accessories: 'Original Box, Fast Charger',
      purchasePrice: 135000.0,
      expectedSalePrice: 150000.0,
      paymentAccountId: 'acc-1',
      paymentMethod: 'cash',
      declarationAgreed: true,
      status: 'in_stock',
      createdBy: 'user-1',
      createdAt: DateTime(2026, 8, 23, 14, 30),
      updatedAt: DateTime(2026, 8, 23, 14, 30),
    );

    const testConfig = ReceiptConfigurationModel(
      shopName: 'FastMobile Store',
      subtitle: 'Sales, Repairs & Used Mobiles',
      phone: '0300-1234567',
      address: 'Shop #12, Hafeez Centre, Lahore',
      paperSize: '80mm',
      showBarcode: true,
      footerMessage: 'Thank you for your business!',
    );

    test('generates valid 80mm PDF document bytes without exception', () async {
      final bytes = await BuyInThermalReceiptService.generateBuyInAgreementPdf(
        purchase: testPurchase,
        config: testConfig,
        staffName: 'Ali Inspector',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(500));
    });

    test('generates valid 58mm PDF document bytes without exception', () async {
      final config58mm = testConfig.copyWith(paperSize: '58mm');
      final bytes = await BuyInThermalReceiptService.generateBuyInAgreementPdf(
        purchase: testPurchase,
        config: config58mm,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(500));
    });

    test('formats textual agreement with seller CNIC and device IMEI', () {
      final text = BuyInThermalReceiptService.formatBuyInText(testPurchase);

      expect(text, contains('USED DEVICE PURCHASE AGREEMENT'));
      expect(text, contains('Hamza Khan'));
      expect(text, contains('35202-9876543-1'));
      expect(text, contains('869234051234567'));
      expect(text, contains('135,000.00'));
      expect(text, contains('LEGAL DECLARATION'));
    });
  });
}
