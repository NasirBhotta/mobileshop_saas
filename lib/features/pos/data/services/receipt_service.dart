import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sale_model.dart';
import '../models/sale_payment_model.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_entitlement_gate.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';

enum ReceiptDeliveryMethod { thermalPrint, whatsapp, email }

extension ReceiptDeliveryMethodX on ReceiptDeliveryMethod {
  String get code {
    switch (this) {
      case ReceiptDeliveryMethod.thermalPrint:
        return 'thermal_print';
      case ReceiptDeliveryMethod.whatsapp:
        return 'whatsapp';
      case ReceiptDeliveryMethod.email:
        return 'email';
    }
  }

  String get label {
    switch (this) {
      case ReceiptDeliveryMethod.thermalPrint:
        return 'Thermal Print';
      case ReceiptDeliveryMethod.whatsapp:
        return 'WhatsApp';
      case ReceiptDeliveryMethod.email:
        return 'Email';
    }
  }
}

class ReceiptService {
  const ReceiptService._();

  static PdfPageFormat _calculatePageFormat(
    ReceiptConfigurationModel config, {
    int contentLines = 25,
  }) {
    final is58mm = config.paperSize.toLowerCase().contains('58');
    final rollWidthMm = is58mm ? 58.0 : 80.0;
    final marginMm = is58mm ? 2.5 : 4.0;

    // Approximate height calculation for continuous thermal paper roll
    final estimatedHeightMm = (90 + (contentLines * 6.5)).clamp(120.0, 1000.0);

    return PdfPageFormat(
      rollWidthMm * PdfPageFormat.mm,
      estimatedHeightMm * PdfPageFormat.mm,
      marginAll: marginMm * PdfPageFormat.mm,
    );
  }

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
      debugPrint('Sales receipt logo load error: $e');
    }
    return null;
  }

  static Future<Uint8List> generateSaleReceiptPdf({
    required SaleModel sale,
    required ReceiptConfigurationModel config,
    String? footer,
    bool isDuplicate = false,
  }) async {
    final pdf = pw.Document();
    final is58mm = config.paperSize.toLowerCase().contains('58');
    final invoice = sale.id?.substring(0, 8).toUpperCase() ?? 'SALE';
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final createdDate = sale.createdAt?.toLocal() ?? DateTime.now();
    final formattedDate = dateFormat.format(createdDate);

    pw.ImageProvider? logoImage;
    if (config.showLogo && config.logoPath != null) {
      logoImage = await _loadLogoImage(config.logoPath);
    }

    // Unicode TrueType font setup with graceful fallback
    pw.Font fontRegular = pw.Font.courier();
    pw.Font fontBold = pw.Font.courierBold();
    try {
      fontRegular = await PdfGoogleFonts.robotoRegular();
      fontBold = await PdfGoogleFonts.robotoBold();
    } catch (_) {}

    final regular = pw.TextStyle(font: fontRegular, fontSize: is58mm ? 7.0 : 8.5);
    final bold = pw.TextStyle(font: fontBold, fontSize: is58mm ? 7.5 : 9.0);
    final titleStyle = pw.TextStyle(font: fontBold, fontSize: is58mm ? 11.0 : 13.5);
    final small = pw.TextStyle(font: fontRegular, fontSize: is58mm ? 6.0 : 7.0);

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

    pw.Widget infoRow(String label, String value, {bool isBold = false}) {
      final style = isBold ? bold : regular;
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: bold),
            pw.SizedBox(width: 4),
            pw.Expanded(
              child: pw.Text(
                value,
                textAlign: pw.TextAlign.right,
                style: style,
              ),
            ),
          ],
        ),
      );
    }

    final totalLines = 20 + (sale.items.length * 2) + sale.payments.length;
    final pageFormat = _calculatePageFormat(config, contentLines: totalLines);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Logo
              if (logoImage != null) ...[
                pw.Center(
                  child: pw.Container(
                    height: is58mm ? 32 : 44,
                    width: is58mm ? 90 : 130,
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                ),
                pw.SizedBox(height: 3),
              ],

              // 2. Shop Header
              pw.Text(
                config.shopName,
                textAlign: pw.TextAlign.center,
                style: titleStyle,
              ),
              if (config.subtitle?.trim().isNotEmpty == true) ...[
                pw.SizedBox(height: 1),
                pw.Text(
                  config.subtitle!.trim(),
                  textAlign: pw.TextAlign.center,
                  style: regular,
                ),
              ],
              if (config.phone?.trim().isNotEmpty == true) ...[
                pw.Text(
                  'Tel: ${config.phone!.trim()}',
                  textAlign: pw.TextAlign.center,
                  style: small,
                ),
              ],
              if (config.email?.trim().isNotEmpty == true) ...[
                pw.Text(
                  'Email: ${config.email!.trim()}',
                  textAlign: pw.TextAlign.center,
                  style: small,
                ),
              ],
              if (config.address?.trim().isNotEmpty == true) ...[
                pw.Text(
                  config.address!.trim(),
                  textAlign: pw.TextAlign.center,
                  style: small,
                ),
              ],

              divider(),

              // 3. Receipt Title & Metadata
              pw.Center(
                child: pw.Text(
                  isDuplicate ? 'DUPLICATE SALES RECEIPT' : 'SALES RECEIPT',
                  style: bold,
                ),
              ),
              pw.SizedBox(height: 2),
              infoRow('Invoice #', invoice, isBold: true),
              infoRow('Date & Time', formattedDate),

              // 4. Customer Details
              if (sale.customerName != null && sale.customerName!.trim().isNotEmpty) ...[
                dashedDivider(),
                infoRow('Customer', sale.customerName!.trim(), isBold: true),
              ],

              divider(),

              // 5. Items Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text('Item Description', style: bold),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('Qty', textAlign: pw.TextAlign.center, style: bold),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Total', textAlign: pw.TextAlign.right, style: bold),
                  ),
                ],
              ),
              dashedDivider(),

              // 6. Items Rows
              ...sale.items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(item.productName, style: bold),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              '@ Rs ${item.unitPrice.toStringAsFixed(0)}${item.discountAmount > 0 ? " (Disc: Rs ${item.discountAmount.toStringAsFixed(0)})" : ""}',
                              style: small,
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Text(
                              '${item.quantity}',
                              textAlign: pw.TextAlign.center,
                              style: regular,
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'Rs ${item.lineTotal.toStringAsFixed(0)}',
                              textAlign: pw.TextAlign.right,
                              style: bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              divider(),

              // 7. Totals Summary
              infoRow('Subtotal', 'Rs ${sale.subtotal.toStringAsFixed(0)}'),
              if (sale.discountAmount > 0)
                infoRow('Discount', '-Rs ${sale.discountAmount.toStringAsFixed(0)}'),
              if (sale.taxAmount > 0)
                infoRow('Tax', 'Rs ${sale.taxAmount.toStringAsFixed(0)}'),

              divider(),
              infoRow('GRAND TOTAL', 'Rs ${sale.total.toStringAsFixed(0)}', isBold: true),
              divider(),

              // 8. Payment Breakdown
              pw.Text('Payment Details:', style: bold),
              pw.SizedBox(height: 1),
              ...sale.payments.map(
                (p) => infoRow(p.method.label, 'Rs ${p.amount.toStringAsFixed(0)}'),
              ),

              // 9. Barcode or QR Code
              if (config.showBarcode || config.showQrCode) ...[
                pw.SizedBox(height: 5),
                pw.Center(
                  child: config.showQrCode
                      ? pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: invoice,
                          width: is58mm ? 45 : 55,
                          height: is58mm ? 45 : 55,
                        )
                      : pw.BarcodeWidget(
                          barcode: pw.Barcode.code128(),
                          data: invoice,
                          width: is58mm ? 130 : 170,
                          height: is58mm ? 26 : 32,
                          drawText: false,
                        ),
                ),
                if (!config.showQrCode)
                  pw.Center(
                    child: pw.Text(invoice, style: small),
                  ),
              ],

              // 10. Terms and Conditions
              if (config.showTerms && config.termsAndConditions.trim().isNotEmpty) ...[
                dashedDivider(),
                pw.Text('Terms & Conditions:', style: bold),
                pw.SizedBox(height: 1),
                pw.Text(
                  config.termsAndConditions.trim(),
                  style: small,
                ),
              ],

              // 11. Customer Signature
              if (config.showCustomerSignature) ...[
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Customer Sign: ________________', style: small),
                  ],
                ),
              ],

              // 12. Footer Message
              () {
                final resolvedFooter = footer?.trim().isNotEmpty == true
                    ? footer!.trim()
                    : (config.footerMessage?.trim().isNotEmpty == true
                        ? config.footerMessage!.trim()
                        : null);
                if (resolvedFooter != null) {
                  return pw.Column(
                    children: [
                      pw.SizedBox(height: 6),
                      pw.Center(
                        child: pw.Text(
                          resolvedFooter,
                          textAlign: pw.TextAlign.center,
                          style: regular,
                        ),
                      ),
                    ],
                  );
                }
                return pw.SizedBox.shrink();
              }(),
              pw.SizedBox(height: 4),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String formatReceipt({
    required SaleModel sale,
    ReceiptConfigurationModel? config,
    String? footer,
    bool duplicate = false,
  }) {
    final cfg = config ?? ReceiptConfigurationModel.defaultConfig();
    final invoice = sale.id?.substring(0, 8).toUpperCase() ?? 'SALE';
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final createdDate = sale.createdAt?.toLocal() ?? DateTime.now();
    final formattedDate = dateFormat.format(createdDate);

    final buffer = StringBuffer()
      ..writeln('================================')
      ..writeln(cfg.shopName.toUpperCase());

    if (cfg.subtitle != null && cfg.subtitle!.trim().isNotEmpty) {
      buffer.writeln(cfg.subtitle!.trim());
    }
    if (cfg.phone != null && cfg.phone!.trim().isNotEmpty) {
      buffer.writeln('Tel: ${cfg.phone!.trim()}');
    }
    if (cfg.address != null && cfg.address!.trim().isNotEmpty) {
      buffer.writeln(cfg.address!.trim());
    }

    buffer
      ..writeln('================================')
      ..writeln(duplicate ? 'DUPLICATE SALES RECEIPT' : 'SALES RECEIPT')
      ..writeln('Invoice #: $invoice')
      ..writeln('Date: $formattedDate');

    if (sale.customerName != null && sale.customerName!.trim().isNotEmpty) {
      buffer.writeln('Customer: ${sale.customerName!.trim()}');
    }

    buffer
      ..writeln('--------------------------------')
      ..writeln('Items:');

    for (final item in sale.items) {
      buffer.writeln(
        '${item.productName} x ${item.quantity} - Rs ${item.lineTotal.toStringAsFixed(0)}',
      );
    }

    buffer
      ..writeln('--------------------------------')
      ..writeln('Subtotal: Rs ${sale.subtotal.toStringAsFixed(0)}');

    if (sale.discountAmount > 0) {
      buffer.writeln('Discount: -Rs ${sale.discountAmount.toStringAsFixed(0)}');
    }
    if (sale.taxAmount > 0) {
      buffer.writeln('Tax: Rs ${sale.taxAmount.toStringAsFixed(0)}');
    }

    buffer
      ..writeln('--------------------------------')
      ..writeln('TOTAL: Rs ${sale.total.toStringAsFixed(0)}')
      ..writeln('--------------------------------')
      ..writeln('Payments:');

    for (final payment in sale.payments) {
      buffer.writeln(
        '${payment.method.label}: Rs ${payment.amount.toStringAsFixed(0)}',
      );
    }

    if (cfg.showTerms && cfg.termsAndConditions.trim().isNotEmpty) {
      buffer
        ..writeln('--------------------------------')
        ..writeln('Terms: ${cfg.termsAndConditions.trim()}');
    }

    final resolvedFooter = footer?.trim().isNotEmpty == true
        ? footer!.trim()
        : (cfg.footerMessage?.trim().isNotEmpty == true
            ? cfg.footerMessage!.trim()
            : null);

    if (resolvedFooter != null) {
      buffer
        ..writeln('--------------------------------')
        ..writeln(resolvedFooter);
    }
    buffer.writeln('================================');

    return buffer.toString();
  }

  static Future<void> deliver({
    required SaleModel sale,
    required ReceiptDeliveryMethod method,
    ReceiptConfigurationModel? config,
    String? footer,
    String? recipient,
    bool duplicate = false,
    required EntitlementEvaluator entitlementEvaluator,
  }) async {
    await PosEntitlementGate(
      entitlementEvaluator,
    ).require('pos.receipt_printing');
    final invoice = sale.id?.substring(0, 8).toUpperCase() ?? 'SALE';
    final resolvedConfig = config ?? ReceiptConfigurationModel.defaultConfig();

    if (method == ReceiptDeliveryMethod.thermalPrint) {
      final bytes = await generateSaleReceiptPdf(
        sale: sale,
        config: resolvedConfig,
        footer: footer,
        isDuplicate: duplicate,
      );
      final totalLines = 20 + (sale.items.length * 2) + sale.payments.length;
      final format = _calculatePageFormat(
        resolvedConfig,
        contentLines: totalLines,
      );
      await Printing.layoutPdf(
        name: '${duplicate ? 'duplicate_' : ''}receipt_$invoice.pdf',
        format: format,
        usePrinterSettings: true,
        onLayout: (_) async => bytes,
      );
      return;
    }

    final text = formatReceipt(
      sale: sale,
      config: resolvedConfig,
      footer: footer,
      duplicate: duplicate,
    );
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject:
            '${duplicate ? 'Duplicate ' : ''}Receipt #$invoice - ${resolvedConfig.shopName}',
      ),
    );
  }

  static Future<bool> printReceipt({
    required SaleModel sale,
    required ReceiptConfigurationModel config,
    String? footer,
    bool duplicate = false,
    required EntitlementEvaluator entitlementEvaluator,
  }) async {
    try {
      await deliver(
        sale: sale,
        method: ReceiptDeliveryMethod.thermalPrint,
        config: config,
        footer: footer,
        duplicate: duplicate,
        entitlementEvaluator: entitlementEvaluator,
      );
      return true;
    } catch (e) {
      debugPrint('Print receipt error: $e');
      return false;
    }
  }

  static Future<void> shareReceiptText({
    required SaleModel sale,
    required ReceiptConfigurationModel config,
    String? footer,
    bool duplicate = false,
    ReceiptDeliveryMethod method = ReceiptDeliveryMethod.whatsapp,
    required EntitlementEvaluator entitlementEvaluator,
  }) async {
    await deliver(
      sale: sale,
      method: method,
      config: config,
      footer: footer,
      duplicate: duplicate,
      entitlementEvaluator: entitlementEvaluator,
    );
  }
}
