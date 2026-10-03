import '../domain/receipt_data.dart';

/// Synthetic fixture only: never persists a sale or changes inventory/ledger.
ReceiptData devReceiptSample() => ReceiptData(
  shopName: 'NIZAAM TEST SHOP',
  shopAddress: 'Development receipt - no sale recorded',
  phone: '0300-1234567',
  invoiceNumber: 'DEV-TEST-001',
  date: DateTime(2026, 10, 2, 14, 30),
  customerName: 'Test Customer',
  items: const [
    ReceiptItem(
      name: 'Samsung Galaxy protective cover with reinforced corners',
      quantity: 2,
      unitPrice: 500,
      itemTotal: 1000,
    ),
    ReceiptItem(
      name: 'USB-C charging cable',
      quantity: 1,
      unitPrice: 350,
      itemTotal: 350,
    ),
  ],
  subtotal: 1350,
  discount: 50,
  grandTotal: 1300,
  paidAmount: 1000,
  remainingAmount: 300,
  paymentMethod: 'Cash + Khata',
  footerMessage: 'Thank you!\nESC/POS development test only',
);
