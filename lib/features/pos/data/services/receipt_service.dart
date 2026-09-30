import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:mobileshop_saas/core/printing/receipt_layout.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sale_model.dart';
import '../models/cart_item_model.dart';
import '../models/sale_payment_model.dart';
import '../models/customer_dashboard_model.dart';
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

  /// Khata is an amount owed, never money received.
  static double paidAmount(SaleModel sale) => sale.payments
      .where((payment) => payment.method != PaymentMethod.credit)
      .fold<double>(0, (sum, payment) => sum + payment.amount);

  static double balanceDue(SaleModel sale) =>
      (sale.total - paidAmount(sale)).clamp(0.0, double.infinity);

  static pw.TableRow _itemRow(
    List<String> cells,
    pw.TextStyle style, {
    bool heading = false,
  }) => pw.TableRow(
    decoration:
        heading ? const pw.BoxDecoration(color: PdfColors.grey200) : null,
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child:
              i == 1
                  ? pw.Text(
                    cells[i],
                    style: style,
                    textDirection: ReceiptLayout.direction(cells[i]),
                  )
                  : pw.SizedBox(
                    height: (style.fontSize ?? 7) * 1.4,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment:
                          i < 3
                              ? pw.Alignment.center
                              : pw.Alignment.centerRight,
                      child: pw.Text(cells[i], style: style),
                    ),
                  ),
        ),
    ],
  );

  static String _formatReceiptItemName(
    CartItemModel item,
    ReceiptConfigurationModel config,
  ) {
    final buffer = StringBuffer(item.productName);
    if (item.deviceDetails != null && item.deviceDetails!.trim().isNotEmpty) {
      buffer.write('\n${item.deviceDetails!.trim()}');
    }
    if (config.showDeviceImei && item.imei != null && item.imei!.trim().isNotEmpty) {
      buffer.write('\nIMEI: ${item.imei!.trim()}');
    }
    return buffer.toString();
  }

  static Future<pw.ImageProvider?> _loadLogoImage(String? logoPath) async {
    if (logoPath == null || logoPath.trim().isEmpty) return null;
    try {
      if (logoPath.startsWith('http://') || logoPath.startsWith('https://')) {
        final netImage = await networkImage(
          logoPath,
        ).timeout(const Duration(seconds: 2));
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
    final invoice = ReceiptLayout.identifier(sale.id, 'SALE');
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final createdDate = sale.createdAt?.toLocal() ?? DateTime.now();
    final formattedDate = dateFormat.format(createdDate);

    pw.ImageProvider? logoImage;
    if (config.showLogo && config.logoPath != null) {
      logoImage = await _loadLogoImage(config.logoPath);
    }

    final fonts = await ReceiptLayout.fonts();
    final regular = pw.TextStyle(
      font: fonts.regular,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 7 : 8.5,
    );
    final bold = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 7 : 8.5,
    );
    final titleStyle = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 13 : 17,
    );
    final small = pw.TextStyle(
      font: fonts.regular,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 6 : 7,
    );

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
                textDirection: ReceiptLayout.direction(value),
                textAlign: pw.TextAlign.right,
                style: style,
              ),
            ),
          ],
        ),
      );
    }

    final pageFormat = ReceiptLayout.pageFormat(config);

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

              ReceiptLayout.header(
                config,
                title: titleStyle,
                regular: regular,
                small: small,
              ),

              divider(),

              // 3. Receipt Title & Metadata
              pw.Center(
                child: pw.Text(
                  isDuplicate ? 'DUPLICATE SALES RECEIPT' : 'SALES RECEIPT',
                  style: bold,
                ),
              ),
              pw.SizedBox(height: 2),
              infoRow('Bill #', invoice, isBold: true),
              infoRow('Date & Time', formattedDate),

              infoRow(
                'Customer',
                sale.customerName?.trim().isNotEmpty == true
                    ? sale.customerName!.trim()
                    : 'COUNTER SALE',
                isBold: true,
              ),
              if (sale.notes?.trim().isNotEmpty == true)
                infoRow('Remarks', sale.notes!.trim()),
              divider(),

              // Per-unit discount matches CartItemModel's pricing semantics.
              pw.Table(
                border: pw.TableBorder.all(width: 0.4),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.4),
                  1: pw.FlexColumnWidth(2.5),
                  2: pw.FlexColumnWidth(0.55),
                  3: pw.FlexColumnWidth(1.2),
                  4: pw.FlexColumnWidth(0.9),
                  5: pw.FlexColumnWidth(1.45),
                },
                children: [
                  _itemRow(
                    ['#', 'Item Details', 'Qty', 'Price', 'Dis.', 'Amount'],
                    small.copyWith(fontWeight: pw.FontWeight.bold),
                    heading: true,
                  ),
                  for (var i = 0; i < sale.items.length; i++)
                    _itemRow([
                      '${i + 1}',
                      _formatReceiptItemName(sale.items[i], config),
                      '${sale.items[i].quantity}',
                      ReceiptLayout.money(sale.items[i].unitPrice),
                      ReceiptLayout.money(sale.items[i].discountAmount),
                      ReceiptLayout.money(sale.items[i].lineTotal),
                    ], small),
                ],
              ),
              pw.SizedBox(height: 3),
              infoRow(
                'Total Qty',
                '${sale.items.fold<int>(0, (sum, item) => sum + item.quantity)}',
              ),
              infoRow('Subtotal', 'Rs ${ReceiptLayout.money(sale.subtotal)}'),
              if (sale.discountAmount > 0)
                infoRow(
                  'Discount',
                  '-Rs ${ReceiptLayout.money(sale.discountAmount)}',
                ),
              if (sale.taxAmount > 0)
                infoRow('Tax', 'Rs ${ReceiptLayout.money(sale.taxAmount)}'),
              pw.SizedBox(height: 3),
              ReceiptLayout.total('GRAND TOTAL', sale.total, bold),
              infoRow(
                'Bill Paid',
                'Rs ${ReceiptLayout.money(paidAmount(sale))}',
              ),
              infoRow(
                'Balance Due',
                'Rs ${ReceiptLayout.money(balanceDue(sale))}',
                isBold: true,
              ),
              if (paidAmount(sale) > sale.total)
                infoRow(
                  'Return / Change',
                  'Rs ${ReceiptLayout.money(paidAmount(sale) - sale.total)}',
                ),
              dashedDivider(),
              ...sale.payments.map(
                (p) => infoRow(
                  p.method.label,
                  'Rs ${ReceiptLayout.money(p.amount)}',
                ),
              ),

              // 9. Barcode or QR Code
              if (config.showBarcode || config.showQrCode) ...[
                pw.SizedBox(height: 5),
                pw.Center(
                  child:
                      config.showQrCode
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
                  pw.Center(child: pw.Text(invoice, style: small)),
              ],

              // 10. Terms and Conditions
              if (config.showTerms &&
                  config.termsAndConditions.trim().isNotEmpty) ...[
                dashedDivider(),
                pw.Text('Terms & Conditions:', style: bold),
                pw.SizedBox(height: 1),
                pw.Text(
                  config.termsAndConditions.trim(),
                  textDirection: ReceiptLayout.direction(
                    config.termsAndConditions,
                  ),
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
                final resolvedFooter =
                    footer?.trim().isNotEmpty == true
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
                          textDirection: ReceiptLayout.direction(
                            resolvedFooter,
                          ),
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
    final invoice = ReceiptLayout.identifier(sale.id, 'SALE');
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final createdDate = sale.createdAt?.toLocal() ?? DateTime.now();
    final formattedDate = dateFormat.format(createdDate);

    final buffer =
        StringBuffer()
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

    if (sale.notes?.trim().isNotEmpty == true) {
      buffer.writeln('Remarks: ${sale.notes!.trim()}');
    }
    buffer
      ..writeln('--------------------------------')
      ..writeln('Items:');

    var itemNumber = 0;
    for (final item in sale.items) {
      buffer.writeln(
        '#${++itemNumber} | Price: Rs ${ReceiptLayout.money(item.unitPrice)} | Dis.: Rs ${ReceiptLayout.money(item.discountAmount)}',
      );
      buffer.writeln(
        '${item.productName} x ${item.quantity} - Rs ${item.lineTotal.toStringAsFixed(0)}',
      );
      if (item.deviceDetails != null && item.deviceDetails!.trim().isNotEmpty) {
        buffer.writeln('  Details: ${item.deviceDetails!.trim()}');
      }
      if (cfg.showDeviceImei && item.imei != null && item.imei!.trim().isNotEmpty) {
        buffer.writeln('  IMEI: ${item.imei!.trim()}');
      }
    }

    buffer
      ..writeln('--------------------------------')
      ..writeln(
        'Total Qty: ${sale.items.fold<int>(0, (sum, item) => sum + item.quantity)}',
      )
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
      ..writeln('Bill Paid: Rs ${ReceiptLayout.money(paidAmount(sale))}')
      ..writeln('Balance Due: Rs ${ReceiptLayout.money(balanceDue(sale))}')
      ..writeln('Payments:');
    if (paidAmount(sale) > sale.total) {
      buffer.writeln(
        'Return / Change: Rs ${ReceiptLayout.money(paidAmount(sale) - sale.total)}',
      );
    }

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

    final resolvedFooter =
        footer?.trim().isNotEmpty == true
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

  static SaleModel previewSale() => SaleModel(
    id: 'DEMO-001',
    branchId: 'demo',
    userId: 'demo',
    customerName: 'COUNTER SALE',
    notes: 'Sample receipt with phone & accessories',
    subtotal: 45700,
    discountAmount: 700,
    taxAmount: 0,
    total: 45000,
    createdAt: DateTime.now(),
    items: const [
      CartItemModel(
        productId: 'demo-phone',
        productName: 'Samsung Galaxy A15',
        deviceDetails: '6GB/128GB • Blue • PTA Approved',
        imei: '864209040123456',
        unitPrice: 45000,
        discountAmount: 700,
        quantity: 1,
      ),
      CartItemModel(
        productId: 'demo-acc',
        productName: 'Fast Charging Adapter 25W',
        unitPrice: 700,
        quantity: 1,
      ),
    ],
    payments: const [
      SalePaymentModel(method: PaymentMethod.cash, amount: 45000),
    ],
  );

  /// Uses demo data only; no sale, inventory or ledger mutation is created.
  static Future<bool> printTestReceipt({
    required ReceiptConfigurationModel config,
  }) async {
    final bytes = await generateSaleReceiptPdf(
      sale: previewSale(),
      config: config,
    );
    return Printing.layoutPdf(
      name: 'TestSalesReceipt.pdf',
      format: ReceiptLayout.pageFormat(config),
      usePrinterSettings: false,
      onLayout: (_) async => bytes,
    );
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
    final invoice = ReceiptLayout.identifier(sale.id, 'SALE');
    final resolvedConfig = config ?? ReceiptConfigurationModel.defaultConfig();

    if (method == ReceiptDeliveryMethod.thermalPrint) {
      final bytes = await generateSaleReceiptPdf(
        sale: sale,
        config: resolvedConfig,
        footer: footer,
        isDuplicate: duplicate,
      );
      final format = ReceiptLayout.pageFormat(resolvedConfig);
      await Printing.layoutPdf(
        name: '${duplicate ? 'duplicate_' : ''}receipt_$invoice.pdf',
        format: format,
        usePrinterSettings: false,
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

  // ══════════════════════════════════════════════════════════════════
  // CUSTOMER SETTLEMENT (UDHAAR PAYMENT) RECEIPT & STATEMENT METHODS
  // ══════════════════════════════════════════════════════════════════

  static Future<Uint8List> generateCustomerSettlementReceiptPdf({
    required ReceiptConfigurationModel config,
    required String customerName,
    String? customerPhone,
    required String settlementId,
    required DateTime date,
    required double previousBalance,
    required double amountPaid,
    required double remainingBalance,
    required String paymentMethod,
    String? notes,
    String? footer,
    bool isDuplicate = false,
  }) async {
    final pdf = pw.Document();
    final is58mm = config.paperSize.toLowerCase().contains('58');
    final slipNo = ReceiptLayout.identifier(settlementId, 'ST');
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final formattedDate = dateFormat.format(date.toLocal());

    pw.ImageProvider? logoImage;
    if (config.showLogo && config.logoPath != null) {
      logoImage = await _loadLogoImage(config.logoPath);
    }

    final fonts = await ReceiptLayout.fonts();
    final regular = pw.TextStyle(
      font: fonts.regular,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 7 : 8.5,
    );
    final bold = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 7 : 8.5,
    );
    final titleStyle = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 13 : 16,
    );
    final subHeaderStyle = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 8.5 : 10.5,
    );
    final highlightStyle = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 8 : 9.5,
    );
    final small = pw.TextStyle(
      font: fonts.regular,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 6 : 7,
    );

    pw.Widget divider() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.0),
      child: pw.Divider(thickness: 0.8, color: PdfColors.grey700),
    );

    pw.Widget dashedDivider() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
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
                textDirection: ReceiptLayout.direction(value),
                textAlign: pw.TextAlign.right,
                style: style,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget amountBox(
      String label,
      double amount, {
      bool isHighlight = false,
      PdfColor? bgColor,
    }) {
      return pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 1.5),
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
        decoration: pw.BoxDecoration(
          color: bgColor ?? (isHighlight ? PdfColors.grey200 : null),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          border: pw.Border.all(
            width: isHighlight ? 0.8 : 0.4,
            color: isHighlight ? PdfColors.black : PdfColors.grey400,
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: isHighlight ? highlightStyle : bold),
            pw.Text(
              'Rs ${ReceiptLayout.money(amount)}',
              style: isHighlight ? highlightStyle : bold,
            ),
          ],
        ),
      );
    }

    final pageFormat = ReceiptLayout.pageFormat(config);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
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
              ReceiptLayout.header(
                config,
                title: titleStyle,
                regular: regular,
                small: small,
              ),
              divider(),
              pw.Center(
                child: pw.Text(
                  isDuplicate
                      ? 'DUPLICATE KHATA RECEIPT'
                      : 'KHATA / UDHAAR PAYMENT RECEIPT',
                  style: subHeaderStyle,
                ),
              ),
              pw.SizedBox(height: 2),
              infoRow('Receipt #', 'ST-$slipNo', isBold: true),
              infoRow('Date & Time', formattedDate),
              infoRow('Customer', customerName, isBold: true),
              if (customerPhone != null && customerPhone.trim().isNotEmpty)
                infoRow('Phone', customerPhone.trim()),
              infoRow('Payment Via', paymentMethod.toUpperCase()),
              if (notes != null && notes.trim().isNotEmpty)
                infoRow('Remarks', notes.trim()),
              divider(),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(
                  'KHATA / BALANCE SUMMARY',
                  textAlign: pw.TextAlign.center,
                  style: small.copyWith(fontWeight: pw.FontWeight.bold),
                ),
              ),
              if (previousBalance > 0)
                amountBox('Kul Udhaar (Total Dues):', previousBalance),
              amountBox(
                'Wasool Shuda (Paid Amount):',
                amountPaid,
                isHighlight: true,
                bgColor: PdfColors.grey100,
              ),
              amountBox(
                'Baaqi Udhaar (Remaining Due):',
                remainingBalance,
                isHighlight: true,
                bgColor: PdfColors.grey200,
              ),
              dashedDivider(),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(
                        width: is58mm ? 50 : 70,
                        height: 0.5,
                        color: PdfColors.grey600,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Customer Sign', style: small),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(
                        width: is58mm ? 50 : 70,
                        height: 0.5,
                        color: PdfColors.grey600,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Authorized Sign', style: small),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              if (footer?.trim().isNotEmpty == true ||
                  config.footerMessage?.trim().isNotEmpty == true) ...[
                dashedDivider(),
                pw.Text(
                  (footer ?? config.footerMessage)!.trim(),
                  style: small,
                  textAlign: pw.TextAlign.center,
                ),
              ],
              pw.Text(
                'Computer generated payment receipt',
                style: small.copyWith(color: PdfColors.grey600),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String formatCustomerSettlementText({
    required ReceiptConfigurationModel config,
    required String customerName,
    String? customerPhone,
    required String settlementId,
    required DateTime date,
    required double previousBalance,
    required double amountPaid,
    required double remainingBalance,
    required String paymentMethod,
    String? notes,
  }) {
    final slipNo = ReceiptLayout.identifier(settlementId, 'ST');
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final formattedDate = dateFormat.format(date.toLocal());
    final shopName = config.shopName;
    final shopPhone = config.phone ?? '';

    final buffer = StringBuffer();
    buffer.writeln('================================');
    buffer.writeln(shopName.toUpperCase());
    buffer.writeln('UDHAAR PAYMENT RECEIPT');
    buffer.writeln('================================');
    buffer.writeln('Slip #: ST-$slipNo');
    buffer.writeln('Date: $formattedDate');
    buffer.writeln(
      'Customer: $customerName${customerPhone != null && customerPhone.isNotEmpty ? ' ($customerPhone)' : ''}',
    );
    buffer.writeln('Payment Via: ${paymentMethod.toUpperCase()}');
    buffer.writeln('--------------------------------');
    if (previousBalance > 0) {
      buffer.writeln('Kul Udhaar (Total Dues): Rs. ${ReceiptLayout.money(previousBalance)}');
    }
    buffer.writeln('Wasool Shuda (Paid):     Rs. ${ReceiptLayout.money(amountPaid)}');
    buffer.writeln('--------------------------------');
    buffer.writeln('BAAQI UDHAAR (Due):      Rs. ${ReceiptLayout.money(remainingBalance)}');
    buffer.writeln('--------------------------------');
    if (notes != null && notes.trim().isNotEmpty) {
      buffer.writeln('Remarks: ${notes.trim()}');
    }
    buffer.writeln('Shukriya!');
    if (shopPhone.isNotEmpty) {
      buffer.writeln(shopPhone);
    }
    buffer.write('================================');
    return buffer.toString();
  }

  static Future<bool> printCustomerSettlementReceipt({
    required ReceiptConfigurationModel config,
    required String customerName,
    String? customerPhone,
    required String settlementId,
    required DateTime date,
    required double previousBalance,
    required double amountPaid,
    required double remainingBalance,
    required String paymentMethod,
    String? notes,
    String? footer,
    bool isDuplicate = false,
    required EntitlementEvaluator entitlementEvaluator,
  }) async {
    try {
      await PosEntitlementGate(
        entitlementEvaluator,
      ).require('pos.receipt_printing');

      final bytes = await generateCustomerSettlementReceiptPdf(
        config: config,
        customerName: customerName,
        customerPhone: customerPhone,
        settlementId: settlementId,
        date: date,
        previousBalance: previousBalance,
        amountPaid: amountPaid,
        remainingBalance: remainingBalance,
        paymentMethod: paymentMethod,
        notes: notes,
        footer: footer,
        isDuplicate: isDuplicate,
      );

      final format = ReceiptLayout.pageFormat(config);
      final slipNo = ReceiptLayout.identifier(settlementId, 'ST');
      await Printing.layoutPdf(
        name: '${isDuplicate ? 'duplicate_' : ''}khata_receipt_$slipNo.pdf',
        format: format,
        usePrinterSettings: false,
        onLayout: (_) async => bytes,
      );
      return true;
    } catch (e) {
      debugPrint('Print customer settlement receipt error: $e');
      rethrow;
    }
  }

  static Future<void> shareCustomerSettlementText({
    required ReceiptConfigurationModel config,
    required String customerName,
    String? customerPhone,
    required String settlementId,
    required DateTime date,
    required double previousBalance,
    required double amountPaid,
    required double remainingBalance,
    required String paymentMethod,
    String? notes,
  }) async {
    final text = formatCustomerSettlementText(
      config: config,
      customerName: customerName,
      customerPhone: customerPhone,
      settlementId: settlementId,
      date: date,
      previousBalance: previousBalance,
      amountPaid: amountPaid,
      remainingBalance: remainingBalance,
      paymentMethod: paymentMethod,
      notes: notes,
    );
    final slipNo = ReceiptLayout.identifier(settlementId, 'ST');
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Khata Receipt #ST-$slipNo - ${config.shopName}',
      ),
    );
  }

  static Future<Uint8List> generateCustomerStatementPdf({
    required ReceiptConfigurationModel config,
    required CustomerDashboardModel dashboard,
    String? footer,
  }) async {
    final pdf = pw.Document();
    final is58mm = config.paperSize.toLowerCase().contains('58');
    final customer = dashboard.customer;
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final formattedDate = dateFormat.format(DateTime.now());

    pw.ImageProvider? logoImage;
    if (config.showLogo && config.logoPath != null) {
      logoImage = await _loadLogoImage(config.logoPath);
    }

    final fonts = await ReceiptLayout.fonts();
    final regular = pw.TextStyle(
      font: fonts.regular,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 7 : 8.5,
    );
    final bold = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 7 : 8.5,
    );
    final titleStyle = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 13 : 16,
    );
    final subHeaderStyle = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 8.5 : 10.5,
    );
    final highlightStyle = pw.TextStyle(
      font: fonts.bold,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 8 : 9.5,
    );
    final small = pw.TextStyle(
      font: fonts.regular,
      fontFallback: [fonts.arabic],
      fontSize: is58mm ? 6 : 7,
    );

    pw.Widget divider() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.0),
      child: pw.Divider(thickness: 0.8, color: PdfColors.grey700),
    );

    pw.Widget dashedDivider() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
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
                textDirection: ReceiptLayout.direction(value),
                textAlign: pw.TextAlign.right,
                style: style,
              ),
            ),
          ],
        ),
      );
    }

    final totalSettled = dashboard.settlements.fold<double>(
      0,
      (sum, s) => sum + s.amount,
    );

    final pageFormat = ReceiptLayout.pageFormat(config);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
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
              ReceiptLayout.header(
                config,
                title: titleStyle,
                regular: regular,
                small: small,
              ),
              divider(),
              pw.Center(
                child: pw.Text(
                  'CUSTOMER KHATA STATEMENT',
                  style: subHeaderStyle,
                ),
              ),
              pw.SizedBox(height: 2),
              infoRow('Date & Time', formattedDate),
              infoRow('Customer', customer.fullName, isBold: true),
              if (customer.phone != null && customer.phone!.isNotEmpty)
                infoRow('Phone', customer.phone!),
              divider(),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(
                  'KHATA OVERVIEW',
                  textAlign: pw.TextAlign.center,
                  style: small.copyWith(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Container(
                margin: const pw.EdgeInsets.symmetric(vertical: 2),
                padding: const pw.EdgeInsets.all(5),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.5, color: PdfColors.grey500),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
                child: pw.Column(
                  children: [
                    infoRow(
                      'Total Purchases (Kharidari):',
                      'Rs ${ReceiptLayout.money(dashboard.lifetimeValue)}',
                    ),
                    infoRow(
                      'Total Paid (Wasooli):',
                      'Rs ${ReceiptLayout.money(totalSettled)}',
                    ),
                    pw.Divider(thickness: 0.4, color: PdfColors.grey400),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('BAAQI UDHAAR (Dues):', style: highlightStyle),
                        pw.Text(
                          'Rs ${ReceiptLayout.money(dashboard.outstandingDues)}',
                          style: highlightStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (dashboard.settlements.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  'RECENT PAYMENTS (WASOOLI)',
                  style: small.copyWith(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Date',
                            style: small.copyWith(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Method',
                            style: small.copyWith(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Text(
                            'Amount',
                            textAlign: pw.TextAlign.right,
                            style: small.copyWith(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    for (final s in dashboard.settlements.take(5))
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text(
                              DateFormat('dd/MM/yy').format(s.createdAt.toLocal()),
                              style: small,
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text(s.method.toUpperCase(), style: small),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text(
                              'Rs ${ReceiptLayout.money(s.amount)}',
                              textAlign: pw.TextAlign.right,
                              style: small.copyWith(fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              dashedDivider(),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(
                        width: is58mm ? 50 : 70,
                        height: 0.5,
                        color: PdfColors.grey600,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Customer Sign', style: small),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(
                        width: is58mm ? 50 : 70,
                        height: 0.5,
                        color: PdfColors.grey600,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Authorized Sign', style: small),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              if (footer?.trim().isNotEmpty == true ||
                  config.footerMessage?.trim().isNotEmpty == true) ...[
                dashedDivider(),
                pw.Text(
                  (footer ?? config.footerMessage)!.trim(),
                  style: small,
                  textAlign: pw.TextAlign.center,
                ),
              ],
              pw.Text(
                'Computer generated statement',
                style: small.copyWith(color: PdfColors.grey600),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String formatCustomerStatementText({
    required ReceiptConfigurationModel config,
    required CustomerDashboardModel dashboard,
  }) {
    final customer = dashboard.customer;
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final formattedDate = dateFormat.format(DateTime.now());
    final shopName = config.shopName;
    final shopPhone = config.phone ?? '';

    final totalSettled = dashboard.settlements.fold<double>(
      0,
      (sum, s) => sum + s.amount,
    );

    final buffer = StringBuffer();
    buffer.writeln('================================');
    buffer.writeln(shopName.toUpperCase());
    buffer.writeln('CUSTOMER KHATA STATEMENT');
    buffer.writeln('================================');
    buffer.writeln('Date: $formattedDate');
    buffer.writeln(
      'Customer: ${customer.fullName}${customer.phone != null && customer.phone!.isNotEmpty ? ' (${customer.phone})' : ''}',
    );
    buffer.writeln('--------------------------------');
    buffer.writeln('Total Purchases (Kharidari): Rs. ${ReceiptLayout.money(dashboard.lifetimeValue)}');
    buffer.writeln('Total Paid (Wasooli):        Rs. ${ReceiptLayout.money(totalSettled)}');
    buffer.writeln('--------------------------------');
    buffer.writeln('BAAQI UDHAAR (Due):          Rs. ${ReceiptLayout.money(dashboard.outstandingDues)}');
    buffer.writeln('================================');
    buffer.writeln('Shukriya!');
    if (shopPhone.isNotEmpty) {
      buffer.writeln(shopPhone);
    }
    return buffer.toString();
  }

  static Future<bool> printCustomerStatement({
    required ReceiptConfigurationModel config,
    required CustomerDashboardModel dashboard,
    String? footer,
    required EntitlementEvaluator entitlementEvaluator,
  }) async {
    try {
      await PosEntitlementGate(
        entitlementEvaluator,
      ).require('pos.receipt_printing');

      final bytes = await generateCustomerStatementPdf(
        config: config,
        dashboard: dashboard,
        footer: footer,
      );

      final format = ReceiptLayout.pageFormat(config);
      final customerId = ReceiptLayout.identifier(
        dashboard.customer.id,
        'CUST',
      );
      await Printing.layoutPdf(
        name: 'khata_statement_$customerId.pdf',
        format: format,
        usePrinterSettings: false,
        onLayout: (_) async => bytes,
      );
      return true;
    } catch (e) {
      debugPrint('Print customer statement error: $e');
      rethrow;
    }
  }

  static Future<void> shareCustomerStatementText({
    required ReceiptConfigurationModel config,
    required CustomerDashboardModel dashboard,
  }) async {
    final text = formatCustomerStatementText(
      config: config,
      dashboard: dashboard,
    );
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject:
            'Khata Statement - ${dashboard.customer.fullName} - ${config.shopName}',
      ),
    );
  }
}
