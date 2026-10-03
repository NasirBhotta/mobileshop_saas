import 'receipt_data.dart';

enum PrinterFailure {
  unavailable,
  connectionTimeout,
  generationFailed,
  sendFailed,
  sendTimeout,
  unsupportedPlatform,
}

class PrinterResult {
  final PrinterFailure? failure;
  final String message;

  const PrinterResult.sent()
    : failure = null,
      message = 'Receipt sent to the emulator';

  const PrinterResult.failed(this.failure, this.message);

  bool get isSuccess => failure == null;
}

abstract interface class PrinterAdapter {
  /// An optional side effect. A successful result means bytes were sent,
  /// not that a physical printer confirmed rendering or paper delivery.
  Future<PrinterResult> printReceipt(ReceiptData receipt);
}

abstract interface class ReceiptByteBuilder {
  Future<List<int>> build(ReceiptData receipt);
}
