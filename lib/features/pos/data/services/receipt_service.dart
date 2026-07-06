import 'package:share_plus/share_plus.dart';

import '../models/sale_model.dart';
import '../models/sale_payment_model.dart';

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
  }) {
    final invoice = sale.id?.substring(0, 8).toUpperCase() ?? 'SALE';
    final text = formatReceipt(
      sale: sale,
      footer: footer,
      duplicate: duplicate,
    );
    return SharePlus.instance.share(
      ShareParams(
        text: text,
        subject:
            '${duplicate ? 'Duplicate ' : ''}Receipt #$invoice via ${method.label}',
      ),
    );
  }
}
