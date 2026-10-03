import 'dart:async';
import 'dart:io';

import '../domain/printer_adapter.dart';
import '../domain/receipt_data.dart';
import 'escpos_config.dart';

typedef PrinterSocketConnector =
    Future<Socket> Function(String host, int port, Duration timeout);

/// DEV ONLY: Escpresso receipt emulator integration.
/// Owns transport only; the builder can be reused with USB/Bluetooth adapters.
class EscPosTcpPrinterAdapter implements PrinterAdapter {
  final ReceiptByteBuilder builder;
  final EscPosConfig config;
  final PrinterSocketConnector _connect;

  EscPosTcpPrinterAdapter({
    required this.builder,
    this.config = const EscPosConfig(),
    PrinterSocketConnector? connect,
  }) : _connect = connect ?? _connectSocket;

  static Future<Socket> _connectSocket(
    String host,
    int port,
    Duration timeout,
  ) => Socket.connect(host, port, timeout: timeout);

  @override
  Future<PrinterResult> printReceipt(ReceiptData receipt) async {
    final List<int> bytes;
    try {
      bytes = await builder.build(receipt);
      if (bytes.isEmpty) {
        throw const FormatException('Receipt contains no bytes');
      }
    } catch (error) {
      return PrinterResult.failed(
        PrinterFailure.generationFailed,
        'Failed to generate receipt: $error',
      );
    }

    final Socket socket;
    try {
      socket = await _connect(config.host, config.port, config.connectTimeout);
    } on TimeoutException {
      return const PrinterResult.failed(
        PrinterFailure.connectionTimeout,
        'Connection timeout',
      );
    } on SocketException catch (error) {
      // Socket.connect reports its native timeout as a SocketException.
      final timedOut = error.message.toLowerCase().contains('timed out');
      return PrinterResult.failed(
        timedOut
            ? PrinterFailure.connectionTimeout
            : PrinterFailure.unavailable,
        timedOut
            ? 'Connection timeout'
            : 'Printer unavailable at ${config.host}:${config.port}',
      );
    } catch (_) {
      return const PrinterResult.failed(
        PrinterFailure.unavailable,
        'Printer unavailable',
      );
    }

    final transportError = Completer<void>();
    StreamSubscription<List<int>>? subscription;
    try {
      subscription = socket.listen(
        (_) {},
        onError: (Object error) {
          if (!transportError.isCompleted) transportError.completeError(error);
        },
      );
      await Future.any([
        _send(socket, bytes),
        transportError.future,
      ]).timeout(config.sendTimeout);
      return const PrinterResult.sent();
    } on TimeoutException {
      return const PrinterResult.failed(
        PrinterFailure.sendTimeout,
        'Failed to send receipt: timeout',
      );
    } catch (_) {
      return const PrinterResult.failed(
        PrinterFailure.sendFailed,
        'Failed to send receipt',
      );
    } finally {
      try {
        socket.destroy();
        await subscription?.cancel().timeout(config.sendTimeout);
      } catch (_) {
        // Cleanup must never turn a handled printer failure into an app error.
      }
    }
  }

  Future<void> _send(Socket socket, List<int> bytes) async {
    socket.add(bytes);
    await socket.flush();
    await socket.close();
  }
}
