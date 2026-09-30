import 'dart:math';

/// Utility to generate unique internal retail barcodes.
/// Uses standard internal-store prefix (20) with valid Mod-10 check digit,
/// fully compliant with Code 128 and EAN-13 barcode readers.
class BarcodeGenerator {
  const BarcodeGenerator._();

  static final _random = Random();

  /// Calculates the Modulo-10 checksum digit for a 12-digit string.
  static int calculateEan13CheckDigit(String code12) {
    if (code12.length != 12) {
      throw ArgumentError('Input must be exactly 12 digits');
    }
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.parse(code12[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    final mod = sum % 10;
    return mod == 0 ? 0 : 10 - mod;
  }

  /// Generates a unique 13-digit retail barcode starting with prefix '20'.
  static String generateUniqueBarcode() {
    // 2 digits prefix: '20' (store internal)
    // 9 digits from current timestamp modulo
    final timePart = (DateTime.now().millisecondsSinceEpoch % 1000000000)
        .toString()
        .padLeft(9, '0');
    // 1 random digit
    final randDigit = _random.nextInt(10).toString();

    final twelveDigits = '20$timePart$randDigit';
    final checkDigit = calculateEan13CheckDigit(twelveDigits);

    return '$twelveDigits$checkDigit';
  }

  /// Preserves existing barcode if present; generates a new unique one if empty.
  static String ensureBarcode(String? existing) {
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    return generateUniqueBarcode();
  }
}
