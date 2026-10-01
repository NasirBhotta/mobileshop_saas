import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/printing/receipt_layout.dart';
import 'package:mobileshop_saas/features/pos/data/models/cart_item_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/data/services/receipt_service.dart';
import 'package:mobileshop_saas/features/repairs/data/services/thermal_receipt_service.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SaleModel sale({List<SalePaymentModel> payments = const [], int count = 2}) =>
      SaleModel(
        id: '123',
        branchId: 'branch',
        userId: 'cashier',
        subtotal: 620,
        discountAmount: 20,
        taxAmount: 0,
        total: 600,
        notes: 'Customer requested black accessories',
        items: List.generate(
          count,
          (i) => CartItemModel(
            productId: '$i',
            productName: 'USB-C charging cable with braided protection - Black',
            quantity: 2,
            unitPrice: 155,
            discountAmount: 5,
          ),
        ),
        payments: payments,
      );

  test(
    'mixed cash and khata prints actual paid amount and outstanding balance',
    () {
      final receipt = sale(
        payments: const [
          SalePaymentModel(method: PaymentMethod.cash, amount: 200),
          SalePaymentModel(method: PaymentMethod.credit, amount: 400),
        ],
      );
      final text = ReceiptService.formatReceipt(sale: receipt);
      expect(text, contains('Invoice #: 123'));
      expect(text, contains('Bill Paid: Rs 200'));
      expect(text, contains('Balance Due: Rs 400'));
      expect(text, contains('Total Qty: 4'));
      expect(text, contains('Price: Rs 155 | Dis.: Rs 5'));
      expect(text, contains('Remarks: Customer requested black accessories'));
      expect(text, isNot(contains('Return / Change:')));
    },
  );

  test('overpayment is change, not a negative balance', () {
    final receipt = sale(
      payments: const [
        SalePaymentModel(method: PaymentMethod.cash, amount: 700),
      ],
    );
    expect(ReceiptService.balanceDue(receipt), 0);
    expect(
      ReceiptService.formatReceipt(sale: receipt),
      contains('Return / Change: Rs 100'),
    );
  });

  for (final width in ['58mm', '80mm']) {
    test(
      '$width offline PDF handles Urdu terms, short IDs and long receipts',
      () async {
        final config = ReceiptConfigurationModel(
          shopName: 'AL-HAMD MOBILE',
          paperSize: width,
          address: 'Basement Firdous Center, Mobile Street, M.B.Din',
          phone: 'Mr. Azeem 0343-2200995\nMr. Umair 0346-2686388',
          subtitle: 'Mobile Accessories & Gadgets',
          logoPath: 'missing-offline-logo.png',
          termsAndConditions:
              'رسید اپنے پاس محفوظ رکھیں۔\nThank you for your visit.',
        );
        final normal = await ReceiptService.generateSaleReceiptPdf(
          sale: ReceiptService.previewSale(),
          config: config,
        );
        final long = await ReceiptService.generateSaleReceiptPdf(
          sale: sale(count: 80),
          config: config,
          isDuplicate: true,
        );
        final repair = await ThermalReceiptService.generateTestReceiptPdf(
          config: config,
        );
        for (final bytes in [normal, long, repair]) {
          expect(String.fromCharCodes(bytes.take(4)), '%PDF');
          final printFormat = ReceiptLayout.printFormat(bytes, config);
          expect(
            printFormat.width,
            (width == '58mm' ? 58 : 80) * PdfPageFormat.mm,
          );
          expect(printFormat.height.isFinite, isTrue);
          expect(printFormat.height, greaterThan(0));
        }
        expect(
          ReceiptLayout.printFormat(long, config).height,
          greaterThan(ReceiptLayout.printFormat(normal, config).height),
        );
        // Opt-in artifacts for visual review without affecting normal test runs.
        final output = Platform.environment['RECEIPT_PREVIEW_DIR'];
        if (output != null) {
          await Directory(output).create(recursive: true);
          await File('$output/sale-$width.pdf').writeAsBytes(normal);
          await File('$output/long-sale-$width.pdf').writeAsBytes(long);
          await File('$output/repair-$width.pdf').writeAsBytes(repair);
        }
      },
    );
  }
}
