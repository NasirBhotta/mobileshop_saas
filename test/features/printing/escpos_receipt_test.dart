import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/printing/domain/printer_adapter.dart';
import 'package:mobileshop_saas/features/printing/domain/receipt_data.dart';
import 'package:mobileshop_saas/features/printing/escpos/escpos_config.dart';
import 'package:mobileshop_saas/features/printing/escpos/escpos_receipt_builder.dart';
import 'package:mobileshop_saas/features/printing/escpos/escpos_tcp_printer.dart';
import 'package:mobileshop_saas/features/printing/integrations/sale_receipt_mapper.dart';
import 'package:mobileshop_saas/features/printing/presentation/dev_receipt_sample.dart';
import 'package:mobileshop_saas/features/pos/data/models/cart_item_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/settings/data/models/receipt_configuration_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('58mm defaults and paper-specific Font A capacity', () {
    const config = EscPosConfig();
    expect(config.host, '127.0.0.1');
    expect(config.port, 9100);
    expect(config.paperSize, PaperSize.mm58);
    expect(config.charactersPerLine, 32);
    expect(const EscPosConfig(paperSize: PaperSize.mm80).charactersPerLine, 48);
  });

  test(
    'long names, unbroken identifiers and multiline text are not truncated',
    () {
      final name = devReceiptSample().items.first.name;
      final lines = wrapReceiptText(name, 32);
      expect(lines.every((line) => line.length <= 32), isTrue);
      expect(lines.join(' '), name);
      final identifier = List.filled(100, 'X').join();
      expect(wrapReceiptText(identifier, 32).join(), identifier);
      expect(wrapReceiptText('Line one\r\nLine two', 32), [
        'Line one',
        'Line two',
      ]);
    },
  );

  test('unsupported scripts and printer control injection fail explicitly', () {
    expect(() => wrapReceiptText('اردو', 32), throwsFormatException);
    expect(
      () => wrapReceiptText('Injected\x1b@command', 32),
      throwsFormatException,
    );
  });

  test(
    'sample contains initialize, alignment, bold, values, feed and cut',
    () async {
      final bytes = await EscPosReceiptBuilder().build(devReceiptSample());
      expect(bytes.take(2), [27, 64]);
      expect(_contains(bytes, [27, 97, 49]), isTrue);
      expect(_contains(bytes, [27, 69, 1]), isTrue);
      expect(_contains(bytes, [27, 100, 3]), isTrue);
      expect(bytes.sublist(bytes.length - 3), [29, 86, 48]);
      final text = latin1.decode(bytes);
      for (final expected in [
        'NIZAAM TEST SHOP',
        'SALE RECEIPT',
        'DEV-TEST-001',
        '02-10-2026 14:30',
        'Qty: 2 @ Rs 500.00',
        '1350.00',
        '50.00',
        '1300.00',
        '1000.00',
        '300.00',
        'Cash + Khata',
      ]) {
        expect(text, contains(expected));
      }
    },
  );

  test(
    'mapper copies existing totals and item discounts without recalculating sale',
    () {
      const item = CartItemModel(
        productId: 'p',
        productName: 'Phone',
        quantity: 2,
        unitPrice: 1000.25,
        discountAmount: 10.25,
        taxRate: 5,
        imei: '123456789012345',
      );
      final date = DateTime.utc(2026, 10, 2);
      final sale = SaleModel(
        id: 'original-full-invoice-id',
        branchId: 'b',
        userId: 'u',
        subtotal: 98765.4321,
        discountAmount: 111.123,
        taxAmount: 222.456,
        total: 88888.888,
        createdAt: date,
        items: const [item],
        payments: const [
          SalePaymentModel(method: PaymentMethod.cash, amount: 500),
          SalePaymentModel(method: PaymentMethod.credit, amount: 88388.888),
        ],
      );
      final receipt = SaleReceiptMapper.map(
        sale,
        const ReceiptConfigurationModel(
          shopName: 'Shop',
          showDeviceImei: false,
        ),
      );
      expect(receipt.invoiceNumber, sale.id);
      expect(receipt.date, same(date));
      expect(receipt.subtotal, sale.subtotal);
      expect(receipt.discount, sale.discountAmount);
      expect(receipt.tax, sale.taxAmount);
      expect(receipt.grandTotal, sale.total);
      expect(receipt.items.single.itemTotal, item.lineTotal);
      expect(receipt.items.single.unitDiscount, item.discountAmount);
      expect(receipt.items.single.imei, item.imei);
      expect(receipt.paidAmount, 500);
      expect(receipt.remainingAmount, sale.total - 500);
      expect(receipt.paymentMethod, 'Cash + Khata');
      expect(() => receipt.items.clear(), throwsUnsupportedError);
    },
  );

  test('missing invoice/date are not replaced by invented values', () {
    const sale = SaleModel(
      branchId: 'b',
      userId: 'u',
      subtotal: 50,
      discountAmount: 0,
      taxAmount: 0,
      total: 50,
    );
    final receipt = SaleReceiptMapper.map(
      sale,
      const ReceiptConfigurationModel(shopName: 'Shop'),
    );
    expect(receipt.date, isNull);
    expect(receipt.invoiceNumber, 'Not recorded');
    expect(receipt.paymentMethod, 'Not recorded');
  });

  test(
    'actual loopback TCP receives the exact builder bytes and EOF',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<List<int>>();
      final listener = server.listen((socket) {
        final bytes = <int>[];
        socket.listen(
          bytes.addAll,
          onDone: () {
            received.complete(bytes);
            socket.destroy();
          },
          onError: received.completeError,
        );
      });
      try {
        final adapter = EscPosTcpPrinterAdapter(
          builder: _Builder([27, 64, 65, 10, 29, 86, 0]),
          config: EscPosConfig(port: server.port),
        );
        final result = await adapter.printReceipt(devReceiptSample());
        expect(result.isSuccess, isTrue);
        expect(await received.future.timeout(const Duration(seconds: 3)), [
          27,
          64,
          65,
          10,
          29,
          86,
          0,
        ]);
      } finally {
        await listener.cancel();
        await server.close();
      }
    },
  );

  test('generation failure never opens the socket', () async {
    final adapter = EscPosTcpPrinterAdapter(
      builder: _Builder(null),
      connect: (_, _, _) async => throw StateError('Must not connect'),
    );
    expect(
      (await adapter.printReceipt(devReceiptSample())).failure,
      PrinterFailure.generationFailed,
    );
  });

  test(
    'connection refused is a meaningful result, not an uncaught error',
    () async {
      final adapter = EscPosTcpPrinterAdapter(
        builder: _Builder([1]),
        connect:
            (_, _, _) async =>
                throw const SocketException('Connection refused'),
      );
      expect(
        (await adapter.printReceipt(devReceiptSample())).failure,
        PrinterFailure.unavailable,
      );
    },
  );

  test(
    'unavailable local port fails safely with the real TCP connector',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final adapter = EscPosTcpPrinterAdapter(
        builder: _Builder([1]),
        config: EscPosConfig(port: port),
      );
      expect(
        (await adapter.printReceipt(devReceiptSample())).failure,
        PrinterFailure.unavailable,
      );
    },
  );

  test('connection timeout is reported', () async {
    final adapter = EscPosTcpPrinterAdapter(
      builder: _Builder([1]),
      connect: (_, _, _) async => throw TimeoutException('Connect'),
    );
    expect(
      (await adapter.printReceipt(devReceiptSample())).failure,
      PrinterFailure.connectionTimeout,
    );
  });

  test('send failure destroys socket and reports failure', () async {
    final socket = _TestSocket(
      flushError: const SocketException('Write failed'),
    );
    final adapter = EscPosTcpPrinterAdapter(
      builder: _Builder([1, 2]),
      connect: (_, _, _) async => socket,
    );
    expect(
      (await adapter.printReceipt(devReceiptSample())).failure,
      PrinterFailure.sendFailed,
    );
    expect(socket.destroyed, isTrue);
  });

  test('send timeout is bounded and destroys socket', () async {
    final socket = _TestSocket(blockFlush: true);
    final adapter = EscPosTcpPrinterAdapter(
      builder: _Builder([1, 2]),
      config: const EscPosConfig(sendTimeout: Duration(milliseconds: 25)),
      connect: (_, _, _) async => socket,
    );
    expect(
      (await adapter.printReceipt(devReceiptSample())).failure,
      PrinterFailure.sendTimeout,
    );
    expect(socket.destroyed, isTrue);
  });
}

bool _contains(List<int> bytes, List<int> sequence) {
  for (var i = 0; i <= bytes.length - sequence.length; i++) {
    if (List.generate(
      sequence.length,
      (j) => bytes[i + j],
    ).asMap().entries.every((entry) => entry.value == sequence[entry.key])) {
      return true;
    }
  }
  return false;
}

class _Builder implements ReceiptByteBuilder {
  final List<int>? bytes;
  _Builder(this.bytes);
  @override
  Future<List<int>> build(ReceiptData receipt) async {
    if (bytes == null) throw const FormatException('Bad fixture');
    return bytes!;
  }
}

class _TestSocket implements Socket {
  final Object? flushError;
  final bool blockFlush;
  bool destroyed = false;
  final _incoming = StreamController<Uint8List>();
  _TestSocket({this.flushError, this.blockFlush = false});
  @override
  void add(List<int> data) {}
  @override
  Future<void> flush() async {
    if (flushError != null) throw flushError!;
    if (blockFlush) await Completer<void>().future;
  }

  @override
  Future<void> close() async {}
  @override
  void destroy() {
    destroyed = true;
    unawaited(_incoming.close());
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
