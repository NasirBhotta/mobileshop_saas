import '../../pos/data/models/sale_model.dart';
import '../../pos/data/models/sale_payment_model.dart';
import '../../settings/data/models/receipt_configuration_model.dart';
import '../domain/receipt_data.dart';

/// Application boundary only. ESC/POS and TCP code never import sale models.
class SaleReceiptMapper {
  static ReceiptData map(
    SaleModel sale,
    ReceiptConfigurationModel config, {
    String? footer,
  }) {
    final paid = sale.payments
        .where((payment) => payment.method != PaymentMethod.credit)
        .fold<double>(0, (total, payment) => total + payment.amount);
    return ReceiptData(
      shopName: config.shopName,
      shopAddress: config.address,
      phone: config.phone,
      invoiceNumber: sale.id ?? 'Not recorded',
      date: sale.createdAt,
      customerName: sale.customerName,
      items:
          sale.items
              .map(
                (item) => ReceiptItem(
                  name: item.productName,
                  quantity: item.quantity,
                  unitPrice: item.unitPrice,
                  itemTotal: item.lineTotal,
                  unitDiscount: item.discountAmount,
                  details: item.deviceDetails,
                  imei: config.showDeviceImei ? item.imei : null,
                ),
              )
              .toList(),
      subtotal: sale.subtotal,
      discount: sale.discountAmount,
      tax: sale.taxAmount,
      grandTotal: sale.total,
      paidAmount: paid,
      remainingAmount: (sale.total - paid).clamp(0.0, double.infinity),
      changeAmount: (paid - sale.total).clamp(0.0, double.infinity),
      paymentMethod:
          sale.payments.isEmpty
              ? 'Not recorded'
              : sale.payments
                  .map((payment) => payment.method.label)
                  .join(' + '),
      footerMessage: config.footerMessage ?? footer,
    );
  }
}
