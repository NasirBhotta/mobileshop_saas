import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sale_model.dart';
import '../models/sale_payment_model.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/features/pos/domain/pos_entitlement_gate.dart';

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

  static String formatReceipt({
    required SaleModel sale,
    String? footer,
    bool duplicate = false,
  }) {
    final invoice = sale.id?.substring(0, 8).toUpperCase() ?? 'SALE';
    final buffer =
        StringBuffer()
          ..writeln(duplicate ? 'DUPLICATE RECEIPT' : 'Receipt')
          ..writeln('Invoice #$invoice')
          ..writeln()
          ..writeln('Items:');

    for (final item in sale.items) {
      buffer.writeln(
        '${item.productName} x ${item.quantity} - Rs ${item.lineTotal.toStringAsFixed(0)}',
      );
    }

    buffer
      ..writeln()
      ..writeln('Subtotal: Rs ${sale.subtotal.toStringAsFixed(0)}');

    if (sale.discountAmount > 0) {
      buffer.writeln('Discount: -Rs ${sale.discountAmount.toStringAsFixed(0)}');
    }
    if (sale.taxAmount > 0) {
      buffer.writeln('Tax: Rs ${sale.taxAmount.toStringAsFixed(0)}');
    }

    buffer
      ..writeln('Total: Rs ${sale.total.toStringAsFixed(0)}')
      ..writeln()
      ..writeln('Payments:');

    for (final payment in sale.payments) {
      buffer.writeln(
        '${payment.method.label}: Rs ${payment.amount.toStringAsFixed(0)}',
      );
    }

    final resolvedFooter = footer?.trim();
    if (resolvedFooter != null && resolvedFooter.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          resolvedFooter.length > 160
              ? resolvedFooter.substring(0, 160)
              : resolvedFooter,
        );
    }
    return buffer.toString();
  }

  static Future<void> deliver({
    required SaleModel sale,
    required ReceiptDeliveryMethod method,
    String? footer,
    String? recipient,
    bool duplicate = false,
    required EntitlementEvaluator entitlementEvaluator,
  }) async {
    await PosEntitlementGate(
      entitlementEvaluator,
    ).require('pos.receipt_printing');
    final invoice = sale.id?.substring(0, 8).toUpperCase() ?? 'SALE';
    if (method == ReceiptDeliveryMethod.thermalPrint) {
      final bytes = await _buildThermalReceipt(
        sale: sale,
        footer: footer,
        duplicate: duplicate,
      );
      await Printing.layoutPdf(
        name: '${duplicate ? 'duplicate_' : ''}receipt_$invoice.pdf',
        format: _thermalPageFormat(sale, footer),
        usePrinterSettings: true,
        onLayout: (_) async => bytes,
      );
      return;
    }

    final text = formatReceipt(
      sale: sale,
      footer: footer,
      duplicate: duplicate,
    );
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject:
            '${duplicate ? 'Duplicate ' : ''}Receipt #$invoice via ${method.label}',
      ),
    );
  }

  static PdfPageFormat _thermalPageFormat(SaleModel sale, String? footer) {
    final footerLines = footer?.trim().isNotEmpty == true ? 3 : 0;
    final estimatedHeightMm =
        92 +
        (sale.items.length * 12) +
        (sale.payments.length * 7) +
        footerLines;
    final height = estimatedHeightMm.clamp(120, 1000).toDouble();
    return PdfPageFormat(
      80 * PdfPageFormat.mm,
      height * PdfPageFormat.mm,
      marginAll: 4 * PdfPageFormat.mm,
    );
  }

  static Future<Uint8List> _buildThermalReceipt({
    required SaleModel sale,
    String? footer,
    required bool duplicate,
  }) async {
    final invoice = sale.id?.substring(0, 8).toUpperCase() ?? 'SALE';
    final document = pw.Document();
    final format = _thermalPageFormat(sale, footer);
    final baseStyle = pw.TextStyle(font: pw.Font.helvetica(), fontSize: 8);
    final boldStyle = pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 8);

    pw.Widget amountRow(String label, String value, {bool bold = false}) {
      final style = bold ? boldStyle : baseStyle;
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: pw.Text(label, style: style)),
            pw.SizedBox(width: 4),
            pw.Text(value, style: style),
          ],
        ),
      );
    }

    document.addPage(
      pw.Page(
        pageFormat: format,
        build:
            (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  duplicate ? 'DUPLICATE RECEIPT' : 'SALES RECEIPT',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 12,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Invoice #$invoice',
                  textAlign: pw.TextAlign.center,
                  style: boldStyle,
                ),
                if (sale.createdAt != null)
                  pw.Text(
                    sale.createdAt!.toLocal().toString().substring(0, 16),
                    textAlign: pw.TextAlign.center,
                    style: baseStyle,
                  ),
                pw.Divider(),
                ...sale.items.expand(
                  (item) => [
                    pw.Text(item.productName, style: boldStyle),
                    amountRow(
                      '${item.quantity} x Rs ${item.unitPrice.toStringAsFixed(0)}',
                      'Rs ${item.lineTotal.toStringAsFixed(0)}',
                    ),
                    pw.SizedBox(height: 2),
                  ],
                ),
                pw.Divider(),
                amountRow('Subtotal', 'Rs ${sale.subtotal.toStringAsFixed(0)}'),
                if (sale.discountAmount > 0)
                  amountRow(
                    'Discount',
                    '-Rs ${sale.discountAmount.toStringAsFixed(0)}',
                  ),
                if (sale.taxAmount > 0)
                  amountRow('Tax', 'Rs ${sale.taxAmount.toStringAsFixed(0)}'),
                pw.Divider(),
                amountRow(
                  'TOTAL',
                  'Rs ${sale.total.toStringAsFixed(0)}',
                  bold: true,
                ),
                pw.SizedBox(height: 5),
                pw.Text('Payments', style: boldStyle),
                ...sale.payments.map(
                  (payment) => amountRow(
                    payment.method.label,
                    'Rs ${payment.amount.toStringAsFixed(0)}',
                  ),
                ),
                if (footer?.trim().isNotEmpty == true) ...[
                  pw.Divider(),
                  pw.Text(
                    footer!.trim(),
                    textAlign: pw.TextAlign.center,
                    style: baseStyle,
                    maxLines: 4,
                  ),
                ],
                pw.SizedBox(height: 8),
              ],
            ),
      ),
    );
    return document.save();
  }
}
