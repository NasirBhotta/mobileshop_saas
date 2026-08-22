import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';

void main() {
  group('ReceiptConfigurationModel', () {
    test('defaultConfig creates model with sensible defaults', () {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Ali Mobile Care',
        phone: '0300-1112233',
        address: 'Shop 5, Hall Road, Lahore',
      );

      expect(config.shopName, equals('Ali Mobile Care'));
      expect(config.phone, equals('0300-1112233'));
      expect(config.address, equals('Shop 5, Hall Road, Lahore'));
      expect(config.paperSize, equals('80mm'));
      expect(config.showLogo, isTrue);
      expect(config.showBarcode, isTrue);
      expect(config.showQrCode, isFalse);
      expect(config.showCustomerPhone, isTrue);
      expect(config.showDeviceColor, isTrue);
      expect(config.showDeviceImei, isTrue);
      expect(config.showTechnician, isTrue);
      expect(config.showEstimatedDate, isTrue);
      expect(config.showTerms, isTrue);
      expect(config.showCustomerSignature, isTrue);
      expect(config.termsAndConditions, contains('warranty'));
      expect(config.footerMessage, contains('Thank you'));
    });

    test('toMap and fromMap serialization roundtrip works accurately', () {
      final original = ReceiptConfigurationModel(
        shopName: 'Fast Fix Wireless',
        subtitle: 'Official Repair Partner',
        phone: '0321-9988776',
        email: 'info@fastfix.pk',
        address: 'Commercial Market, Rawalpindi',
        logoPath: '/storage/emulated/0/logo.png',
        showLogo: true,
        paperSize: '58mm',
        showBarcode: false,
        showQrCode: true,
        showCustomerPhone: false,
        showDeviceColor: true,
        showDeviceImei: true,
        showTechnician: false,
        showEstimatedDate: true,
        showTerms: true,
        termsAndConditions: 'Custom shop repair policy.',
        showCustomerSignature: false,
        footerMessage: 'We appreciate your trust!',
        updatedAt: DateTime.parse('2026-08-22T10:00:00.000Z'),
      );

      final map = original.toMap();
      final restored = ReceiptConfigurationModel.fromMap(map);

      expect(restored.shopName, equals(original.shopName));
      expect(restored.subtitle, equals(original.subtitle));
      expect(restored.phone, equals(original.phone));
      expect(restored.email, equals(original.email));
      expect(restored.address, equals(original.address));
      expect(restored.logoPath, equals(original.logoPath));
      expect(restored.showLogo, equals(original.showLogo));
      expect(restored.paperSize, equals('58mm'));
      expect(restored.showBarcode, isFalse);
      expect(restored.showQrCode, isTrue);
      expect(restored.showCustomerPhone, isFalse);
      expect(restored.showDeviceColor, isTrue);
      expect(restored.showDeviceImei, isTrue);
      expect(restored.showTechnician, isFalse);
      expect(restored.showEstimatedDate, isTrue);
      expect(restored.showTerms, isTrue);
      expect(restored.termsAndConditions, equals('Custom shop repair policy.'));
      expect(restored.showCustomerSignature, isFalse);
      expect(restored.footerMessage, equals('We appreciate your trust!'));
    });

    test('copyWith updates specified fields only', () {
      final initial = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Original Shop',
      );

      final updated = initial.copyWith(
        shopName: 'Updated Shop Name',
        paperSize: '58mm',
        showBarcode: false,
        showQrCode: true,
      );

      expect(updated.shopName, equals('Updated Shop Name'));
      expect(updated.paperSize, equals('58mm'));
      expect(updated.showBarcode, isFalse);
      expect(updated.showQrCode, isTrue);
      // Unchanged fields remain preserved
      expect(updated.showTerms, equals(initial.showTerms));
      expect(updated.termsAndConditions, equals(initial.termsAndConditions));
    });
  });
}
