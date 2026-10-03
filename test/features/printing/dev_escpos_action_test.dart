import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/printing/domain/printer_adapter.dart';
import 'package:mobileshop_saas/features/printing/domain/receipt_data.dart';
import 'package:mobileshop_saas/features/printing/escpos/escpos_config.dart';
import 'package:mobileshop_saas/features/printing/presentation/dev_escpos_receipt_action.dart';

void main() {
  testWidgets('development action requires explicit opt-in', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: DevEscPosReceiptAction())),
      ),
    );
    expect(
      find.byIcon(Icons.science_outlined),
      EscPosConfig.devEnabled ? findsOneWidget : findsNothing,
    );
  });

  if (EscPosConfig.devEnabled) {
    testWidgets('sample printer failure is shown without affecting screen', (
      tester,
    ) async {
      final printer = _UnavailablePrinter();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [DevEscPosReceiptAction(printer: printer)],
              ),
              body: const Text('Existing receipt'),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Receipt - Dev'));
      await tester.pumpAndSettle();
      expect(printer.receipt?.invoiceNumber, 'DEV-TEST-001');
      expect(find.text('Printer unavailable'), findsOneWidget);
      expect(find.text('Existing receipt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _UnavailablePrinter implements PrinterAdapter {
  ReceiptData? receipt;
  @override
  Future<PrinterResult> printReceipt(ReceiptData receipt) async {
    this.receipt = receipt;
    return const PrinterResult.failed(
      PrinterFailure.unavailable,
      'Printer unavailable',
    );
  }
}
