import '../domain/printer_adapter.dart';
import '../domain/receipt_data.dart';
import 'escpos_config.dart';

PrinterAdapter createDevPrinter({EscPosConfig config = const EscPosConfig()}) =>
    _UnsupportedPrinter();

class _UnsupportedPrinter implements PrinterAdapter {
  @override
  Future<PrinterResult> printReceipt(ReceiptData receipt) async =>
      const PrinterResult.failed(
        PrinterFailure.unsupportedPlatform,
        'Raw TCP receipt testing requires the Windows or Android app',
      );
}
