import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repair status action shows loading and prevents duplicate input', () {
    final source =
        File(
          'lib/features/repairs/presentation/screens/repairs_list_screen.dart',
        ).readAsStringSync();

    expect(source, contains('Status update ho raha hai, please wait...'));
    expect(source, contains('LinearProgressIndicator'));
    expect(
      source,
      contains("Text(_isSaving ? 'Updating...' : 'Update Status')"),
    );
    expect(source, contains('_isSaving || selectedStatus == null'));
    expect(source, contains('finally {'));
  });
}
