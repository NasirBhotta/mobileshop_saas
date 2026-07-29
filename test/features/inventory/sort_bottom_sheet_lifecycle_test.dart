import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sort menu does not use a widget ref after the menu future completes',
    () {
      final source =
          File(
            'lib/features/inventory/presentation/widgets/sort_bottom_sheet.dart',
          ).readAsStringSync();

      expect(
        source,
        contains(
          'final sortController = ref.read(sortOptionProvider.notifier);',
        ),
      );
      expect(source, contains('sortController.state = selectedOption;'));
      expect(
        source,
        isNot(
          contains(
            'ref.read(sortOptionProvider.notifier).state = selectedOption;',
          ),
        ),
      );
      expect(source, contains('class _SortSheet extends ConsumerWidget'));
      expect(source, contains('builder: (_) => const _SortSheet()'));
    },
  );
}
