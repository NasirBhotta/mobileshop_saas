import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../domain/printer_adapter.dart';
import '../domain/receipt_data.dart';
import 'escpos_config.dart';

/// Generates ESC/POS bytes without opening a socket or touching application data.
class EscPosReceiptBuilder implements ReceiptByteBuilder {
  final EscPosConfig config;
  Future<CapabilityProfile>? _profile;

  EscPosReceiptBuilder({this.config = const EscPosConfig()});

  @override
  Future<List<int>> build(ReceiptData receipt) async {
    final profile = await (_profile ??= CapabilityProfile.load());
    final generator = Generator(config.paperSize, profile);
    final width = config.charactersPerLine;
    final bytes = <int>[
      ...generator.reset(),
      ...generator.setGlobalFont(PosFontType.fontA, maxCharsPerLine: width),
    ];

    void text(String value, {bool bold = false, bool center = false}) {
      for (final line in wrapReceiptText(value, width)) {
        bytes.addAll(
          generator.text(
            line,
            styles: PosStyles(
              bold: bold,
              align: center ? PosAlign.center : PosAlign.left,
            ),
            maxCharsPerLine: width,
          ),
        );
      }
    }

    void amount(String label, double value, {bool bold = false}) {
      if (!value.isFinite) {
        throw const FormatException('Invalid receipt amount');
      }
      final formatted = 'Rs ${value.toStringAsFixed(2)}';
      final spacing = width - label.length - formatted.length;
      if (spacing > 0) {
        text('$label${' ' * spacing}$formatted', bold: bold);
      } else {
        text(label, bold: bold);
        text(formatted, bold: bold);
      }
    }

    text(receipt.shopName, bold: true, center: true);
    if (receipt.shopAddress?.isNotEmpty == true) {
      text(receipt.shopAddress!, center: true);
    }
    if (receipt.phone?.isNotEmpty == true) text(receipt.phone!, center: true);
    text('SALE RECEIPT', bold: true, center: true);
    text('Invoice: ${receipt.invoiceNumber}');
    text(
      'Date: ${receipt.date == null ? 'Not recorded' : DateFormat('dd-MM-yyyy HH:mm').format(receipt.date!.toLocal())}',
    );
    if (receipt.customerName?.isNotEmpty == true) {
      text('Customer: ${receipt.customerName}');
    }
    text('-' * width);
    for (final item in receipt.items) {
      text(item.name, bold: true);
      if (item.details?.isNotEmpty == true) text(item.details!);
      if (item.imei?.isNotEmpty == true) text('IMEI: ${item.imei}');
      if (!item.unitPrice.isFinite) {
        throw const FormatException('Invalid item price');
      }
      text('Qty: ${item.quantity} @ Rs ${item.unitPrice.toStringAsFixed(2)}');
      if (item.unitDiscount != 0) amount('Discount / unit', item.unitDiscount);
      amount('Item total', item.itemTotal);
    }
    text('-' * width);
    amount('Subtotal', receipt.subtotal);
    if (receipt.discount != 0) amount('Discount', receipt.discount);
    if (receipt.tax != 0) amount('Tax', receipt.tax);
    amount('TOTAL', receipt.grandTotal, bold: true);
    amount('Paid', receipt.paidAmount);
    if (receipt.remainingAmount != 0) {
      amount('Remaining', receipt.remainingAmount);
    }
    if (receipt.changeAmount != 0) amount('Change', receipt.changeAmount);
    text('Payment: ${receipt.paymentMethod}');
    if (receipt.footerMessage?.isNotEmpty == true) {
      text(receipt.footerMessage!, center: true);
    }
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());
    return bytes;
  }
}

/// Wrap at spaces, splitting long unbroken names without dropping characters.
/// Initial emulator text mode deliberately supports printable ASCII only;
/// unsupported scripts and ESC/POS control injection fail explicitly.
List<String> wrapReceiptText(String value, int width) {
  if (width <= 0) throw ArgumentError.value(width, 'width');
  final normalized = value.replaceAll('\r\n', '\n');
  if (normalized.runes.any((rune) => rune != 10 && (rune < 32 || rune > 126))) {
    throw const FormatException(
      'Emulator text mode requires printable English/ASCII text. '
      'Urdu and other scripts need a raster-text builder.',
    );
  }
  final lines = <String>[];
  for (var remaining in normalized.split('\n')) {
    while (remaining.length > width) {
      final space = remaining.lastIndexOf(' ', width);
      final end = space > 0 ? space : width;
      lines.add(remaining.substring(0, end));
      remaining = remaining.substring(end + (space > 0 ? 1 : 0));
    }
    lines.add(remaining);
  }
  return lines;
}
