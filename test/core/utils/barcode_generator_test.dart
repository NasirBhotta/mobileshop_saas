import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/utils/barcode_generator.dart';

void main() {
  group('BarcodeGenerator', () {
    test('generateUniqueBarcode creates a 13-digit valid retail barcode', () {
      final barcode1 = BarcodeGenerator.generateUniqueBarcode();
      final barcode2 = BarcodeGenerator.generateUniqueBarcode();

      expect(barcode1.length, 13);
      expect(barcode2.length, 13);
      expect(barcode1.startsWith('20'), isTrue);
      expect(barcode2.startsWith('20'), isTrue);
      expect(barcode1 != barcode2, isTrue); // unique
    });

    test('calculateEan13CheckDigit generates accurate mod 10 check digit', () {
      // Known EAN-13 example: 4006381333931
      final checkDigit = BarcodeGenerator.calculateEan13CheckDigit('400638133393');
      expect(checkDigit, 1);
    });

    test('ensureBarcode preserves existing barcode and generates new if empty or null', () {
      expect(BarcodeGenerator.ensureBarcode('1234567890123'), '1234567890123');
      expect(BarcodeGenerator.ensureBarcode('  '), isNot(equals('  ')));
      expect(BarcodeGenerator.ensureBarcode(null).length, 13);
    });
  });
}
