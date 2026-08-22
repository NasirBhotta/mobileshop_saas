import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';

class ThermalReceiptService {
  const ThermalReceiptService._();

  static PdfPageFormat _calculatePageFormat(
    ReceiptConfigurationModel config, {
    int contentLines = 25,
  }) {
    final is58mm = config.paperSize.toLowerCase().contains('58');
    final rollWidthMm = is58mm ? 58.0 : 80.0;
    final marginMm = is58mm ? 2.5 : 4.0;

    // Approximate height calculation for continuous thermal paper roll
    final estimatedHeightMm = (85 + (contentLines * 5.5)).clamp(120.0, 800.0);

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
      debugPrint('Thermal receipt logo load error: $e');
    }
    return null;
  }

  static Future<Uint8List> generateRepairTicketPdf({
    required RepairTicketModel ticket,
    required ReceiptConfigurationModel config,
    double? advancePaid,
    bool isDuplicate = false,
  }) async {
    final pdf = pw.Document();
    final is58mm = config.paperSize.toLowerCase().contains('58');
    final ticketNo = ticket.ticketNo ?? ticket.id.substring(0, 8).toUpperCase();
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final createdDate = ticket.createdAt?.toLocal() ?? DateTime.now();
    final formattedDate = dateFormat.format(createdDate);

    pw.ImageProvider? logoImage;
    if (config.showLogo && config.logoPath != null) {
      logoImage = await _loadLogoImage(config.logoPath);
    }

    // Unicode supported font styles
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
            pw.Text('$label:', style: bold),
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

    final cost = ticket.totalCost ?? ticket.estimatedCost;
    final paid = advancePaid ?? 0.0;
    final balance = cost != null ? (cost - paid).clamp(0.0, 99999999.0) : null;

    pdf.addPage(
      pw.Page(
        pageFormat: _calculatePageFormat(config, contentLines: 30),
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
              if (config.address?.trim().isNotEmpty == true) ...[
                pw.Text(
                  config.address!.trim(),
                  textAlign: pw.TextAlign.center,
                  style: small,
                ),
              ],

              divider(),

              // 3. Ticket Intake Header
              pw.Center(
                child: pw.Text(
                  isDuplicate ? 'DUPLICATE REPAIR RECEIPT' : 'REPAIR INTAKE RECEIPT',
                  style: bold,
                ),
              ),
              pw.SizedBox(height: 2),
              infoRow('Ticket No', ticketNo, isBold: true),
              infoRow('Date & Time', formattedDate),
              infoRow('Status', ticket.status.label.toUpperCase()),

              divider(),

              // 4. Customer Details
              infoRow('Customer', ticket.customerName, isBold: true),
              if (config.showCustomerPhone && ticket.customerPhone?.trim().isNotEmpty == true)
                infoRow('Phone', ticket.customerPhone!),

              dashedDivider(),

              // 5. Device Details
              infoRow('Device', '${ticket.deviceBrand} ${ticket.deviceModel}'.trim(), isBold: true),
              if (config.showDeviceColor && ticket.deviceColor?.trim().isNotEmpty == true)
                infoRow('Color', ticket.deviceColor!),
              if (config.showDeviceImei && ticket.imei?.trim().isNotEmpty == true)
                infoRow('IMEI / Serial', ticket.imei!),
              if (config.showTechnician && ticket.technicianId?.trim().isNotEmpty == true)
                infoRow('Technician', ticket.technicianId!),
              if (config.showEstimatedDate && ticket.estimatedCompletionAt != null)
                infoRow(
                  'Est. Completion',
                  DateFormat('dd-MMM-yyyy').format(ticket.estimatedCompletionAt!.toLocal()),
                ),

              divider(),

              // 6. Fault & Issue Description
              pw.Text('Reported Fault / Problem:', style: bold),
              pw.SizedBox(height: 1),
              pw.Container(
                padding: const pw.EdgeInsets.all(3.0),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
                child: pw.Text(ticket.faultDescription, style: regular),
              ),

              divider(),

              // 7. Cost & Payment Details
              if (cost != null && cost > 0) ...[
                infoRow(
                  ticket.totalCost != null ? 'Total Bill' : 'Estimated Cost',
                  'Rs ${cost.toStringAsFixed(0)}',
                  isBold: true,
                ),
              ],
              if (paid > 0) ...[
                infoRow('Advance Paid', 'Rs ${paid.toStringAsFixed(0)}'),
                if (balance != null)
                  infoRow(
                    'Balance Due',
                    'Rs ${balance.toStringAsFixed(0)}',
                    isBold: true,
                  ),
              ],

              // 8. Barcode or QR Code
              if (config.showBarcode || config.showQrCode) ...[
                pw.SizedBox(height: 4),
                pw.Center(
                  child: config.showQrCode
                      ? pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: ticketNo,
                          width: is58mm ? 45 : 55,
                          height: is58mm ? 45 : 55,
                        )
                      : pw.BarcodeWidget(
                          barcode: pw.Barcode.code128(),
                          data: ticketNo,
                          width: is58mm ? 130 : 170,
                          height: is58mm ? 26 : 32,
                          drawText: false,
                        ),
                ),
                if (!config.showQrCode)
                  pw.Center(
                    child: pw.Text(ticketNo, style: small),
                  ),
              ],

              // 9. Terms and Conditions
              if (config.showTerms && config.termsAndConditions.trim().isNotEmpty) ...[
                dashedDivider(),
                pw.Text('Terms & Conditions:', style: bold),
                pw.SizedBox(height: 1),
                pw.Text(
                  config.termsAndConditions.trim(),
                  style: small,
                ),
              ],

              // 10. Customer Signature
              if (config.showCustomerSignature) ...[
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Customer Sign: ________________', style: small),
                  ],
                ),
              ],

              // 11. Footer Message
              if (config.footerMessage?.trim().isNotEmpty == true) ...[
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pw.Text(
                    config.footerMessage!.trim(),
                    textAlign: pw.TextAlign.center,
                    style: regular,
                  ),
                ),
              ],
              pw.SizedBox(height: 4),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> generateTestReceiptPdf({
    required ReceiptConfigurationModel config,
  }) async {
    final sampleTicket = RepairTicketModel(
      id: 'demo-ticket-sample-1234',
      ticketNo: 'TK-DEMO-001',
      tenantId: 'demo-tenant',
      branchId: 'demo-branch',
      customerName: 'Muhammad Ali',
      customerPhone: '0300-1234567',
      deviceBrand: 'Samsung',
      deviceModel: 'Galaxy S23 Ultra',
      deviceColor: 'Phantom Black',
      imei: '864209040123456',
      faultDescription: 'Screen glass broken, touch working fine. Display replacement requested.',
      status: RepairTicketStatus.inProgress,
      estimatedCost: 18500,
      technicianId: 'Master Tech Asif',
      estimatedCompletionAt: DateTime.now().add(const Duration(days: 2)),
      createdBy: 'demo-user',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    return generateRepairTicketPdf(
      ticket: sampleTicket,
      config: config,
      advancePaid: 5000,
      isDuplicate: false,
    );
  }

  static Future<bool> printRepairTicket({
    required RepairTicketModel ticket,
    required ReceiptConfigurationModel config,
    double? advancePaid,
    bool isDuplicate = false,
  }) async {
    try {
      final ticketNo = ticket.ticketNo ?? ticket.id.substring(0, 8).toUpperCase();
      final bytes = await generateRepairTicketPdf(
        ticket: ticket,
        config: config,
        advancePaid: advancePaid,
        isDuplicate: isDuplicate,
      );

      final format = _calculatePageFormat(config);

      return await Printing.layoutPdf(
        name: 'RepairTicket_$ticketNo.pdf',
        format: format,
        usePrinterSettings: true,
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      debugPrint('Thermal receipt print failed: $e');
      return false;
    }
  }

  static Future<bool> printTestReceipt({
    required ReceiptConfigurationModel config,
  }) async {
    try {
      final bytes = await generateTestReceiptPdf(config: config);
      final format = _calculatePageFormat(config);

      return await Printing.layoutPdf(
        name: 'TestReceipt_${config.shopName}.pdf',
        format: format,
        usePrinterSettings: true,
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      debugPrint('Test receipt print failed: $e');
      return false;
    }
  }

  static String formatRepairTicketText({
    required RepairTicketModel ticket,
    required ReceiptConfigurationModel config,
    double? advancePaid,
    bool isDuplicate = false,
  }) {
    final ticketNo = ticket.ticketNo ?? ticket.id.substring(0, 8).toUpperCase();
    final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');
    final createdDate = ticket.createdAt?.toLocal() ?? DateTime.now();
    final formattedDate = dateFormat.format(createdDate);

    final buffer = StringBuffer()
      ..writeln('================================')
      ..writeln(config.shopName.toUpperCase())
      ..writeln(config.subtitle ?? 'Expert Smartphone Repairs')
      ..writeln('================================')
      ..writeln(isDuplicate ? 'DUPLICATE REPAIR RECEIPT' : 'REPAIR INTAKE RECEIPT')
      ..writeln('Ticket #: $ticketNo')
      ..writeln('Date: $formattedDate')
      ..writeln('Status: ${ticket.status.label}')
      ..writeln('--------------------------------')
      ..writeln('Customer: ${ticket.customerName}')
      ..writeln('Device: ${ticket.deviceBrand} ${ticket.deviceModel}');

    if (ticket.customerPhone != null && ticket.customerPhone!.isNotEmpty) {
      buffer.writeln('Phone: ${ticket.customerPhone}');
    }
    if (ticket.imei != null && ticket.imei!.isNotEmpty) {
      buffer.writeln('IMEI: ${ticket.imei}');
    }

    buffer
      ..writeln('--------------------------------')
      ..writeln('Fault: ${ticket.faultDescription}')
      ..writeln('--------------------------------');

    final cost = ticket.totalCost ?? ticket.estimatedCost;
    if (cost != null && cost > 0) {
      buffer.writeln('Est. Cost: Rs ${cost.toStringAsFixed(0)}');
    }
    final paid = advancePaid ?? 0.0;
    if (paid > 0) {
      buffer.writeln('Advance Paid: Rs ${paid.toStringAsFixed(0)}');
      if (cost != null) {
        final balance = (cost - paid).clamp(0.0, 9999999.0);
        buffer.writeln('Balance: Rs ${balance.toStringAsFixed(0)}');
      }
    }

    if (config.showTerms && config.termsAndConditions.isNotEmpty) {
      buffer
        ..writeln('--------------------------------')
        ..writeln('Terms: ${config.termsAndConditions}');
    }

    if (config.footerMessage != null && config.footerMessage!.isNotEmpty) {
      buffer
        ..writeln('--------------------------------')
        ..writeln(config.footerMessage);
    }
    buffer.writeln('================================');

    return buffer.toString();
  }

  static Future<void> shareRepairTicket({
    required RepairTicketModel ticket,
    required ReceiptConfigurationModel config,
    double? advancePaid,
    bool isDuplicate = false,
  }) async {
    final ticketNo = ticket.ticketNo ?? ticket.id.substring(0, 8).toUpperCase();
    final text = formatRepairTicketText(
      ticket: ticket,
      config: config,
      advancePaid: advancePaid,
      isDuplicate: isDuplicate,
    );
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Repair Ticket #$ticketNo - ${config.shopName}',
      ),
    );
  }
}
