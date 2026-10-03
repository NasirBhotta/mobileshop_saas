/// Printing DTOs only: no database entities, state management or printer APIs.
class ReceiptItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final double itemTotal;
  final double unitDiscount;
  final String? details;
  final String? imei;

  const ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.itemTotal,
    this.unitDiscount = 0,
    this.details,
    this.imei,
  });
}

class ReceiptData {
  final String shopName;
  final String? shopAddress;
  final String? phone;
  final String invoiceNumber;
  final DateTime? date;
  final String? customerName;
  final List<ReceiptItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double grandTotal;
  final double paidAmount;
  final double remainingAmount;
  final double changeAmount;
  final String paymentMethod;
  final String? footerMessage;

  ReceiptData({
    required this.shopName,
    this.shopAddress,
    this.phone,
    required this.invoiceNumber,
    this.date,
    this.customerName,
    required List<ReceiptItem> items,
    required this.subtotal,
    required this.discount,
    this.tax = 0,
    required this.grandTotal,
    required this.paidAmount,
    required this.remainingAmount,
    this.changeAmount = 0,
    required this.paymentMethod,
    this.footerMessage,
  }) : items = List.unmodifiable(items);
}
