import 'package:printing/printing.dart';

import '../../../../core/printing/sticker_layout.dart';
import '../../../../core/utils/barcode_generator.dart';
import '../../../buyin/data/models/customer_purchase_model.dart';
import '../models/product_model.dart';

/// Service to generate and print 50mm x 30mm thermal label stickers.
class ProductStickerService {
  const ProductStickerService._();

  /// Prints 50mm x 30mm barcode sticker(s) for a standard inventory product.
  static Future<bool> printProductSticker({
    required ProductModel product,
    required String shopName,
    String? imei,
    String? details,
    int copies = 1,
  }) async {
    final barcode = BarcodeGenerator.ensureBarcode(product.barcode);
    final subtitle = details?.trim().isNotEmpty == true
        ? details!.trim()
        : (product.description?.trim().isNotEmpty == true
            ? product.description!.trim()
            : (product.sku?.trim().isNotEmpty == true
                ? 'SKU: ${product.sku!.trim()}'
                : null));

    final bytes = await StickerLayout.generateStickerPdf(
      shopName: shopName,
      title: product.name,
      subtitle: subtitle,
      barcode: barcode,
      price: product.salePrice,
      imei: imei,
      copies: copies,
    );

    return Printing.layoutPdf(
      name: 'Sticker_${product.name}_$barcode.pdf',
      format: StickerLayout.format50x30,
      usePrinterSettings: true,
      onLayout: (_) async => bytes,
    );
  }

  /// Prints 50mm x 30mm barcode sticker for a customer purchase (Used Phone).
  /// The barcode and human-readable text will explicitly use the phone's exact IMEI.
  static Future<bool> printCustomerPurchaseSticker({
    required CustomerPurchaseModel purchase,
    required String shopName,
    int copies = 1,
  }) async {
    final specs = [
      purchase.storage,
      purchase.color,
      purchase.deviceCondition != null
          ? 'Cond: ${purchase.deviceCondition}'
          : null,
    ].where((e) => e != null && e.trim().isNotEmpty).join(' • ');

    final bytes = await StickerLayout.generateStickerPdf(
      shopName: shopName,
      title: purchase.productName,
      subtitle: specs.isNotEmpty ? specs : null,
      barcode: purchase.imei1.trim(),
      price: purchase.expectedSalePrice > 0
          ? purchase.expectedSalePrice
          : purchase.purchasePrice,
      imei: purchase.imei1.trim(),
      copies: copies,
    );

    return Printing.layoutPdf(
      name: 'Sticker_Used_${purchase.imei1}.pdf',
      format: StickerLayout.format50x30,
      usePrinterSettings: true,
      onLayout: (_) async => bytes,
    );
  }

  /// Prints a test 50mm x 30mm barcode sticker to verify roll alignment,
  /// print darkness, and barcode readability on thermal label printers.
  static Future<bool> printTestSticker({
    required String shopName,
  }) async {
    final bytes = await StickerLayout.generateStickerPdf(
      shopName: shopName.isNotEmpty ? shopName : 'MOBILE SHOP',
      title: 'Demo Smartphone Pro',
      subtitle: '8GB/128GB • Midnight Black',
      barcode: '202609300018',
      price: 45000,
      imei: '864209040123456',
      copies: 1,
    );

    return Printing.layoutPdf(
      name: 'Test_Sticker_50x30.pdf',
      format: StickerLayout.format50x30,
      usePrinterSettings: true,
      onLayout: (_) async => bytes,
    );
  }
}
