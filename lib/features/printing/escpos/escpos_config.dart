import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// DEV ONLY: Escpresso receipt emulator integration. All configuration lives here.
class EscPosConfig {
  static const devEnabled = bool.fromEnvironment('NIZAAM_ESCPOS_DEV');

  final String host;
  final int port;
  final PaperSize paperSize;
  final Duration connectTimeout;
  final Duration sendTimeout;

  const EscPosConfig({
    this.host = '127.0.0.1',
    this.port = 9100,
    this.paperSize = PaperSize.mm58,
    this.connectTimeout = const Duration(seconds: 3),
    this.sendTimeout = const Duration(seconds: 5),
  });

  /// Conservative Font A capacity, not the paper width in millimetres.
  int get charactersPerLine => switch (paperSize) {
    PaperSize.mm58 => 32,
    PaperSize.mm72 => 42,
    PaperSize.mm80 => 48,
    _ => 32,
  };
}
