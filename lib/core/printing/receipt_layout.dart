import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/settings/data/models/receipt_configuration_model.dart';

/// Shared, offline-safe typography and roll layout for sales and repairs.
class ReceiptLayout {
  static Future<({pw.Font regular, pw.Font bold, pw.Font arabic})>? _fonts;

  static Future<({pw.Font regular, pw.Font bold, pw.Font arabic})> fonts() =>
      _fonts ??= _loadFonts();

  static Future<({pw.Font regular, pw.Font bold, pw.Font arabic})>
  _loadFonts() async {
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final arabic = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    return (
      regular: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      arabic: pw.Font.ttf(arabic),
    );
  }

  static PdfPageFormat pageFormat(ReceiptConfigurationModel config) {
    final narrow = config.paperSize.contains('58');
    // Let the PDF page measure the content; long names/terms must not be clipped.
    return PdfPageFormat(
      (narrow ? 58 : 80) * PdfPageFormat.mm,
      double.infinity,
      marginAll: (narrow ? 2.5 : 4) * PdfPageFormat.mm,
    );
  }

  static String identifier(String? id, String fallback) {
    if (id == null || id.isEmpty) return fallback;
    return (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();
  }

  static String money(num amount) =>
      NumberFormat('#,##0.##', 'en').format(amount);

  static pw.TextDirection direction(String text) =>
      RegExp(r'[\u0600-\u06ff]').hasMatch(text)
          ? pw.TextDirection.rtl
          : pw.TextDirection.ltr;

  static pw.Widget header(
    ReceiptConfigurationModel config, {
    required pw.TextStyle title,
    required pw.TextStyle regular,
    required pw.TextStyle small,
  }) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text(
        config.shopName,
        style: title,
        textAlign: pw.TextAlign.center,
        textDirection: direction(config.shopName),
      ),
      for (final value in [
        config.address,
        config.phone,
        config.email,
        config.subtitle,
      ])
        if (value?.trim().isNotEmpty == true)
          pw.Text(
            value!.trim(),
            style: value == config.subtitle ? regular : small,
            textAlign: pw.TextAlign.center,
            textDirection: direction(value),
          ),
    ],
  );

  static pw.Widget total(String label, num amount, pw.TextStyle style) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(4),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border.all(width: 0.6),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(label, style: style)),
            pw.Text('Rs ${money(amount)}', style: style),
          ],
        ),
      );
}
