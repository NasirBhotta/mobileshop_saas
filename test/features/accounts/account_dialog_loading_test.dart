import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account save dialog blocks duplicate taps and shows progress', () {
    final source =
        File(
          'lib/features/accounts/presentation/screens/accounts_screen.dart',
        ).readAsStringSync();
    final dialog = source.substring(
      source.indexOf('Future<void> _showAccountDialog'),
      source.indexOf('Future<void> _showEntryDialog'),
    );

    expect(dialog, contains('var saving = false'));
    expect(dialog, contains('setState(() => saving = true)'));
    expect(dialog, contains('setState(() => saving = false)'));
    expect(dialog, contains("Text('Saving...')"));
    expect(dialog, contains('CircularProgressIndicator'));
  });
}
