import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mobileshop_saas/features/buyin/data/models/customer_purchase_model.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';

class BuyInThermalReceiptService {
  const BuyInThermalReceiptService._();

  static Future<pw.ImageProvider?> _loadLogoImage(String? logoPath) async {
    if (logoPath == null || logoPath.trim().isEmpty) return null;
    try {
      if (logoPath.startsWith('http://') || logoPath.startsWith('https://')) {
        final netImage = await networkImage(logoPath);
        return netImage;
      }
      final file = File(logoPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return pw.MemoryImage(bytes);
      }
    } catch (e) {
      debugPrint('BuyIn receipt logo load error: $e');
    }
    return null;
  }

  static Future<Uint8List> generateBuyInAgreementPdf({
    required CustomerPurchaseModel purchase,
    required ReceiptConfigurationModel config,
    String? staffName,
  }) async {
    final pdf = pw.Document();
    final is58mm = config.paperSize.toLowerCase().contains('58');
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final formattedDate = dateFormat.format(purchase.createdAt.toLocal());
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    pw.ImageProvider? logoImage;
    if (config.showLogo && config.logoPath != null) {
      logoImage = await _loadLogoImage(config.logoPath);
    }

    // Unicode TrueType font setup with fallback
    pw.Font fontRegular = pw.Font.courier();
    pw.Font fontBold = pw.Font.courierBold();
    try {
      fontRegular = await PdfGoogleFonts.robotoRegular();
      fontBold = await PdfGoogleFonts.robotoBold();
    } catch (_) {}

    final regular = pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7.0 : 8.5);
    final bold = pw.TextStyle(font: fontBold, fontSize: is58mm ? 7.5 : 9.0);
    final titleStyle = pw.TextStyle(font: fontBold, fontSize: is58mm ? 10.5 : 13.0);
    final small = pw.TextStyle(font: fontRegular, fontSize: is58mm ? 6.0 : 7.0);
    final smallBold = pw.TextStyle(font: fontBold, fontSize: is58mm ? 6.0 : 7.0);

    pw.Widget divider() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3.0),
          child: pw.Divider(thickness: 0.8, color: PdfColors.grey700),
        );

    pw.Widget dashedDivider() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3.0),
          child: pw.Text(
            '- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -',
            textAlign: pw.TextAlign.center,
            style: small,
            maxLines: 1,
          ),
        );

    pw.Widget rowItem(String label, String value, {bool isValueBold = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: is58mm ? 60 : 85,
              child: pw.Text(label, style: smallBold),
            ),
            pw.Text(': ', style: small),
            pw.Expanded(
              child: pw.Text(
                value,
                style: isValueBold ? bold : regular,
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    final rollWidthMm = is58mm ? 58.0 : 80.0;
    final marginMm = is58mm ? 2.5 : 4.0;
    final estimatedHeightMm = is58mm ? 230.0 : 250.0;

    final pageFormat = PdfPageFormat(
      rollWidthMm * PdfPageFormat.mm,
      estimatedHeightMm * PdfPageFormat.mm,
      marginAll: marginMm * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // ── Shop Header ──
              if (logoImage != null) ...[
                pw.Center(
                  child: pw.Container(
                    height: is58mm ? 32 : 45,
                    width: is58mm ? 90 : 130,
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                ),
                pw.SizedBox(height: 3),
              ],
              pw.Text(
                config.shopName.toUpperCase(),
                style: titleStyle,
                textAlign: pw.TextAlign.center,
              ),
              if (config.subtitle != null && config.subtitle!.trim().isNotEmpty)
                pw.Text(
                  config.subtitle!,
                  style: small,
                  textAlign: pw.TextAlign.center,
                ),
              if (config.phone != null && config.phone!.trim().isNotEmpty)
                pw.Text(
                  'Phone: ${config.phone!}',
                  style: small,
                  textAlign: pw.TextAlign.center,
                ),
              if (config.address != null && config.address!.trim().isNotEmpty)
                pw.Text(
                  config.address!,
                  style: small,
                  textAlign: pw.TextAlign.center,
                ),

              divider(),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                child: pw.Text(
                  'USED DEVICE PURCHASE AGREEMENT',
                  style: bold,
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text('Date: $formattedDate', style: small),
              if (staffName != null && staffName.trim().isNotEmpty)
                pw.Text('Intake Staff: $staffName', style: small),

              divider(),

              // ── Seller Info (Mandatory Legal Record) ──
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('SELLER (CUSTOMER) DETAILS', style: smallBold),
              ),
              pw.SizedBox(height: 2),
              rowItem('Seller Name', purchase.sellerName, isValueBold: true),
              rowItem('CNIC Number', purchase.sellerCnic, isValueBold: true),
              rowItem('Contact Phone', purchase.sellerPhone),
              if (purchase.sellerAddress != null && purchase.sellerAddress!.trim().isNotEmpty)
                rowItem('Address', purchase.sellerAddress!),

              dashedDivider(),

              // ── Device Info ──
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('DEVICE SPECIFICATIONS', style: smallBold),
              ),
              pw.SizedBox(height: 2),
              rowItem('Model', purchase.productName, isValueBold: true),
              rowItem('IMEI 1', purchase.imei1, isValueBold: true),
              if (purchase.imei2 != null && purchase.imei2!.trim().isNotEmpty)
                rowItem('IMEI 2', purchase.imei2!),
              if (purchase.color != null && purchase.color!.trim().isNotEmpty)
                rowItem('Color', purchase.color!),
              if (purchase.storage != null && purchase.storage!.trim().isNotEmpty)
                rowItem('Storage/RAM', purchase.storage!),
              if (purchase.deviceCondition != null && purchase.deviceCondition!.trim().isNotEmpty)
                rowItem('Condition', purchase.deviceCondition!),
              if (purchase.accessories != null && purchase.accessories!.trim().isNotEmpty)
                rowItem('Accessories', purchase.accessories!),

              dashedDivider(),

              // ── Financials ──
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('PAYMENT DETAILS', style: smallBold),
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('PURCHASE COST PAID:', style: bold),
                  pw.Text(
                    'Rs. ${currencyFormat.format(purchase.purchasePrice)}',
                    style: titleStyle,
                  ),
                ],
              ),
              if (purchase.paymentMethod != null && purchase.paymentMethod!.trim().isNotEmpty)
                rowItem('Payment Mode', purchase.paymentMethod!.toUpperCase()),

              divider(),

              // ── Legal Declaration & Undertaking ──
              pw.Text(
                'LEGAL UNDERTAKING & DECLARATION',
                style: smallBold,
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'I hereby declare and confirm that I am the legitimate and sole owner of the aforementioned mobile device. This device is not stolen, lost, or linked to any unlawful activities. I have voluntarily sold this device to the shop along with full ownership transfer.',
                style: small,
                textAlign: pw.TextAlign.justify,
              ),

              pw.SizedBox(height: 12),

              // ── Signatures ──
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(
                        width: is58mm ? 65 : 85,
                        child: pw.Divider(thickness: 0.8),
                      ),
                      pw.Text('Seller Signature', style: smallBold),
                      pw.Text('(CNIC Attached)', style: small),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(
                        width: is58mm ? 65 : 85,
                        child: pw.Divider(thickness: 0.8),
                      ),
                      pw.Text('Shopkeeper Stamp', style: smallBold),
                      pw.Text('& Signature', style: small),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 6),

              // ── Barcode & QR Code ──
              if (config.showBarcode && purchase.imei1.isNotEmpty) ...[
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: purchase.imei1,
                    width: is58mm ? 120 : 160,
                    height: is58mm ? 24 : 32,
                    drawText: true,
                    textStyle: small,
                  ),
                ),
                pw.SizedBox(height: 4),
              ],

              if (config.footerMessage != null && config.footerMessage!.trim().isNotEmpty) ...[
                pw.Text(
                  config.footerMessage!,
                  style: small,
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> printBuyInAgreement({
    required CustomerPurchaseModel purchase,
    required ReceiptConfigurationModel config,
    String? staffName,
  }) async {
    final bytes = await generateBuyInAgreementPdf(
      purchase: purchase,
      config: config,
      staffName: staffName,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => bytes,
      name: 'BuyIn_${purchase.imei1}_${DateFormat('yyyyMMdd').format(purchase.createdAt)}',
    );
  }

  static Future<void> shareBuyInText(CustomerPurchaseModel purchase) async {
    final text = formatBuyInText(purchase);
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Used Device Buy-In Agreement - IMEI: ${purchase.imei1}',
      ),
    );
  }

  static String formatBuyInText(CustomerPurchaseModel purchase) {
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final formattedDate = dateFormat.format(purchase.createdAt.toLocal());
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    final sb = StringBuffer();
    sb.writeln('====================================');
    sb.writeln(' USED DEVICE PURCHASE AGREEMENT ');
    sb.writeln('====================================');
    sb.writeln('Date: $formattedDate');
    sb.writeln('------------------------------------');
    sb.writeln('SELLER DETAILS:');
    sb.writeln('Name : ${purchase.sellerName}');
    sb.writeln('CNIC : ${purchase.sellerCnic}');
    sb.writeln('Phone: ${purchase.sellerPhone}');
    if (purchase.sellerAddress != null && purchase.sellerAddress!.trim().isNotEmpty) {
      sb.writeln('Address: ${purchase.sellerAddress}');
    }
    sb.writeln('------------------------------------');
    sb.writeln('DEVICE SPECIFICATIONS:');
    sb.writeln('Model: ${purchase.productName}');
    sb.writeln('IMEI 1: ${purchase.imei1}');
    if (purchase.imei2 != null && purchase.imei2!.trim().isNotEmpty) {
      sb.writeln('IMEI 2: ${purchase.imei2}');
    }
    if (purchase.color != null && purchase.color!.trim().isNotEmpty) {
      sb.writeln('Color: ${purchase.color}');
    }
    if (purchase.storage != null && purchase.storage!.trim().isNotEmpty) {
      sb.writeln('Storage: ${purchase.storage}');
    }
    if (purchase.deviceCondition != null && purchase.deviceCondition!.trim().isNotEmpty) {
      sb.writeln('Condition: ${purchase.deviceCondition}');
    }
    if (purchase.accessories != null && purchase.accessories!.trim().isNotEmpty) {
      sb.writeln('Accessories: ${purchase.accessories}');
    }
    sb.writeln('------------------------------------');
    sb.writeln('PURCHASE AMOUNT: Rs. ${currencyFormat.format(purchase.purchasePrice)}');
    if (purchase.paymentMethod != null && purchase.paymentMethod!.trim().isNotEmpty) {
      sb.writeln('Payment Mode: ${purchase.paymentMethod!.toUpperCase()}');
    }
    sb.writeln('------------------------------------');
    sb.writeln('LEGAL DECLARATION:');
    sb.writeln('The seller confirms that the device is legally owned and not stolen.');
    sb.writeln('====================================');
    return sb.toString();
  }
}
