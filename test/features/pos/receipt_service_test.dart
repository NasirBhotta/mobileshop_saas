import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/data/models/cart_item_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_dashboard_model.dart';
import 'package:mobileshop_saas/features/pos/data/services/receipt_service.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptService with ReceiptConfigurationModel', () {
    final sampleSale = SaleModel(
      id: 'sale-uuid-987654321',
      branchId: 'branch-001',
      customerId: 'cust-123',
      customerName: 'Muhammad Rizwan',
      userId: 'cashier-001',
      status: SaleStatus.completed,
      subtotal: 95000,
      discountAmount: 2000,
      taxAmount: 500,
      total: 93500,
      items: const [
        CartItemModel(
          productId: 'prod-001',
          productName: 'iPhone 13 Pro Screen Protector',
          productSku: 'ACC-IP13P-SP',
          unitPrice: 1500,
          quantity: 2,
          discountAmount: 0,
        ),
        CartItemModel(
          productId: 'prod-002',
          productName: 'Apple iPhone 12 128GB Black',
          productSku: 'PHN-IP12-128B',
          unitPrice: 92000,
          quantity: 1,
          discountAmount: 2000,
        ),
      ],
      payments: const [
        SalePaymentModel(
          method: PaymentMethod.cash,
          amount: 50000,
        ),
        SalePaymentModel(
          method: PaymentMethod.card,
          amount: 43500,
        ),
      ],
      createdAt: DateTime(2026, 8, 24, 13, 45),
    );

    test('generateSaleReceiptPdf generates valid 80mm PDF bytes with custom shop branding', () async {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Master Mobile Zone',
        phone: '0300-9876543',
        address: 'Shop 12, Hafeez Centre, Lahore',
      ).copyWith(
        subtitle: 'Complete Mobile Sales & Solutions',
        showBarcode: true,
        showQrCode: false,
        showTerms: true,
        termsAndConditions: '1. Check items before leaving counter.\n2. No refund without original invoice.',
        showCustomerSignature: true,
        footerMessage: 'Thank you for shopping with Master Mobile Zone!',
      );

      final bytes = await ReceiptService.generateSaleReceiptPdf(
        sale: sampleSale,
        config: config,
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('generateSaleReceiptPdf generates valid 58mm PDF bytes with QR code and duplicate flag', () async {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Fast POS Mini',
      ).copyWith(
        paperSize: '58mm',
        showBarcode: false,
        showQrCode: true,
        showCustomerSignature: false,
      );

      final bytes = await ReceiptService.generateSaleReceiptPdf(
        sale: sampleSale,
        config: config,
        isDuplicate: true,
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('formatReceipt plain-text contains custom shop name, items, totals, payments, and terms', () {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Al-Madina Mobiles',
        phone: '0312-1112233',
        address: 'Main Bazar, Gujranwala',
      ).copyWith(
        subtitle: 'All Brands Mobile & Accessories',
        showTerms: true,
        termsAndConditions: 'Return accepted within 3 days.',
        footerMessage: 'Software warranty only.',
      );

      final text = ReceiptService.formatReceipt(
        sale: sampleSale,
        config: config,
        duplicate: false,
      );

      expect(text, contains('AL-MADINA MOBILES'));
      expect(text, contains('All Brands Mobile & Accessories'));
      expect(text, contains('Tel: 0312-1112233'));
      expect(text, contains('Main Bazar, Gujranwala'));
      expect(text, contains('SALES RECEIPT'));
      expect(text, contains('Invoice #: SALE-UUI'));
      expect(text, contains('Muhammad Rizwan'));
      expect(text, contains('iPhone 13 Pro Screen Protector x 2 - Rs 3000'));
      expect(text, contains('Apple iPhone 12 128GB Black x 1 - Rs 90000'));
      expect(text, contains('Subtotal: Rs 95000'));
      expect(text, contains('Discount: -Rs 2000'));
      expect(text, contains('Tax: Rs 500'));
      expect(text, contains('TOTAL: Rs 93500'));
      expect(text, contains('Cash: Rs 50000'));
      expect(text, contains('Card: Rs 43500'));
      expect(text, contains('Terms: Return accepted within 3 days.'));
      expect(text, contains('Software warranty only.'));
    });

    test('formatReceipt falls back to defaultConfig when config is null', () {
      final text = ReceiptService.formatReceipt(
        sale: sampleSale,
        config: null,
      );

      expect(text, contains('MOBILE CARE & SERVICES'));
      expect(text, contains('SALES RECEIPT'));
      expect(text, contains('TOTAL: Rs 93500'));
    });

    test('generateCustomerSettlementReceiptPdf generates valid PDF bytes with udhaar summary', () async {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Ali Electronics & Mobile',
        phone: '0300-1234567',
        address: 'Bano Bazar, Lahore',
      );

      final bytes = await ReceiptService.generateCustomerSettlementReceiptPdf(
        config: config,
        customerName: 'Muhammad Amir',
        customerPhone: '0321-7654321',
        settlementId: 'settle-uuid-112233',
        date: DateTime(2026, 9, 29, 17, 30),
        previousBalance: 25000,
        amountPaid: 10000,
        remainingBalance: 15000,
        paymentMethod: 'cash',
        notes: 'Partial khata payment',
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('formatCustomerSettlementText contains total udhaar, paid amount and remaining balance', () {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Bhotta Mobile Centre',
        phone: '0300-5555555',
      );

      final text = ReceiptService.formatCustomerSettlementText(
        config: config,
        customerName: 'Ali Raza',
        customerPhone: '0345-9998877',
        settlementId: 'st-998877',
        date: DateTime(2026, 9, 29, 16, 0),
        previousBalance: 50000,
        amountPaid: 20000,
        remainingBalance: 30000,
        paymentMethod: 'jazzcash',
        notes: 'Monthly installment received',
      );

      expect(text, contains('BHOTTA MOBILE CENTRE'));
      expect(text, contains('UDHAAR PAYMENT RECEIPT'));
      expect(text, contains('Ali Raza'));
      expect(text, contains('(0345-9998877)'));
      expect(text, contains('Payment Via: JAZZCASH'));
      expect(text, contains('Kul Udhaar (Total Dues): Rs. 50,000'));
      expect(text, contains('Wasool Shuda (Paid):     Rs. 20,000'));
      expect(text, contains('BAAQI UDHAAR (Due):      Rs. 30,000'));
      expect(text, contains('Monthly installment received'));
      expect(text, contains('Shukriya!'));
    });

    test('generateCustomerStatementPdf and formatCustomerStatementText produce statement', () async {
      final config = ReceiptConfigurationModel.defaultConfig(
        shopName: 'Master Telecom',
        phone: '0311-2223334',
      );

      final dashboard = CustomerDashboardModel(
        customer: const CustomerModel(
          id: 'cust-001',
          tenantId: 'tenant-1',
          branchId: 'b-1',
          fullName: 'Tariq Mehmood',
          phone: '0301-4445556',
        ),
        lifetimeValue: 120000,
        outstandingDues: 35000,
        activeRepairTickets: 1,
        settlements: [
          CustomerSettlementModel(
            id: 'st-01',
            customerId: 'cust-001',
            branchId: 'b-1',
            userId: 'u-1',
            amount: 25000,
            method: 'cash',
            createdAt: DateTime(2026, 9, 20),
          ),
        ],
      );

      final pdfBytes = await ReceiptService.generateCustomerStatementPdf(
        config: config,
        dashboard: dashboard,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(pdfBytes.take(4)), equals('%PDF'));

      final text = ReceiptService.formatCustomerStatementText(
        config: config,
        dashboard: dashboard,
      );

      expect(text, contains('MASTER TELECOM'));
      expect(text, contains('CUSTOMER KHATA STATEMENT'));
      expect(text, contains('Tariq Mehmood'));
      expect(text, contains('Total Purchases (Kharidari): Rs. 120,000'));
      expect(text, contains('Total Paid (Wasooli):        Rs. 25,000'));
      expect(text, contains('BAAQI UDHAAR (Due):          Rs. 35,000'));
    });
  });
}
