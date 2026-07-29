import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repair completion uses a bounded searchable inventory picker', () {
    final source =
        File(
          'lib/features/repairs/presentation/widgets/repair_completion_dialog.dart',
        ).readAsStringSync();

    expect(source, contains('Search inventory part'));
    expect(source, contains('Product name, SKU, barcode or category'));
    expect(source, contains('_searchRepairInventoryProducts'));
    expect(source, contains('!product.isActive || product.stock <= 0'));
    expect(source, contains('tokens.every(searchable.contains)'));
    expect(source, contains('matches.take(50).toList()'));
    expect(source, contains('qty > product.stock'));
  });
}
