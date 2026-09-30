import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/printing/sticker_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StickerLayout', () {
    test('generateStickerPdf produces non-empty PDF bytes for regular product', () async {
      final bytes = await StickerLayout.generateStickerPdf(
        shopName: 'Speed-X Mobile Center',
        title: 'Original Fast Charger 25W Type-C',
        barcode: '2026093012345',
        price: 1850,
        subtitle: 'ACC-CHG-25W',
        copies: 1,
      );

      expect(bytes, isNotEmpty);
      // PDF documents start with %PDF
      final header = String.fromCharCodes(bytes.take(4));
      expect(header, '%PDF');
    });

    test('generateStickerPdf produces valid PDF with IMEI badge and multi-copies', () async {
      final bytes = await StickerLayout.generateStickerPdf(
        shopName: 'Al-Madina Mobile Zone',
        title: 'iPhone 13 128GB Midnight',
        barcode: '356892110293847',
        price: 145000,
        imei: '356892110293847',
        subtitle: '128GB • 88% Battery • PTA Approved',
        copies: 2,
      );

      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.take(4));
      expect(header, '%PDF');
    });
  });
}
