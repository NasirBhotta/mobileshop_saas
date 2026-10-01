import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt_layout.dart';

/// 50mm x 30mm Thermal Label Sticker Layout for direct thermal label printers
/// such as Speed X SP-690UB, Xprinter, Rongta, etc.
class StickerLayout {
  const StickerLayout._();

  /// Standard 50 x 30 mm thermal sticker page format. Keep the content clear
  /// of the unprintable edges common on desktop thermal label printers.
  static final PdfPageFormat format50x30 = PdfPageFormat(
    50 * PdfPageFormat.mm,
    30 * PdfPageFormat.mm,
    marginLeft: 3 * PdfPageFormat.mm,
    marginRight: 3 * PdfPageFormat.mm,
    marginTop: 1.5 * PdfPageFormat.mm,
    marginBottom: 1.5 * PdfPageFormat.mm,
  );

  /// Generates a PDF containing [copies] of a single product/unit thermal sticker.
  static Future<Uint8List> generateStickerPdf({
    required String shopName,
    required String title,
    String? subtitle,
    required String barcode,
    required double price,
    String? imei,
    int copies = 1,
  }) async {
    final pdf = pw.Document();
    final fonts = await ReceiptLayout.fonts();

    final currencyFmt = NumberFormat('#,##0', 'en');
    final formattedPrice = 'Rs ${currencyFmt.format(price)}';
    final effectiveCopies = copies.clamp(1, 200);

    for (var i = 0; i < effectiveCopies; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: format50x30,
          build: (context) {
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // 1. Header: Shop Name & Price
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          shopName.trim().toUpperCase(),
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 6.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                          textDirection: ReceiptLayout.direction(shopName),
                        ),
                      ),
                      if (price > 0)
                        pw.Text(
                          formattedPrice,
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                    ],
                  ),

                  pw.SizedBox(height: 1),

                  // 2. Product Name / Title
                  pw.Text(
                    title.trim(),
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 7.0,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    textDirection: ReceiptLayout.direction(title),
                  ),

                  // 3. Subtitle / Details (specs, color, condition, or SKU)
                  if (subtitle != null && subtitle.trim().isNotEmpty)
                    pw.Text(
                      subtitle.trim(),
                      style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 5.5,
                        color: PdfColors.grey800,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),

                  pw.SizedBox(height: 1.5),

                  // 4. Code 128 Barcode
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: barcode.trim(),
                        drawText: false,
                        width: double.infinity,
                        height: 20,
                      ),
                    ),
                  ),

                  pw.SizedBox(height: 1),

                  // 5. Human readable code / IMEI
                  pw.Center(
                    child: pw.Text(
                      imei != null && imei.trim().isNotEmpty
                          ? 'IMEI: ${imei.trim()}'
                          : barcode.trim(),
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 6.5,
                        letterSpacing: 0.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return pdf.save();
  }
}
