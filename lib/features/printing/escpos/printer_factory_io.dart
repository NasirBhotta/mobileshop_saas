import '../domain/printer_adapter.dart';
import 'escpos_config.dart';
import 'escpos_receipt_builder.dart';
import 'escpos_tcp_printer.dart';

PrinterAdapter createDevPrinter({EscPosConfig config = const EscPosConfig()}) =>
    EscPosTcpPrinterAdapter(
      builder: EscPosReceiptBuilder(config: config),
      config: config,
    );
