import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile more sheet scrolls in constrained and keyboard viewports', () {
    final source = File(
      'lib/shared/widgets/mobile_nav.dart',
    ).readAsStringSync();

    expect(source, contains('showModalBottomSheet<void>'));
    expect(source, contains('SingleChildScrollView'));
    expect(source, contains('mainAxisSize: MainAxisSize.min'));
  });
}
