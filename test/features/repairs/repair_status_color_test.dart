import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every repair status has a distinct badge color mapping', () {
    final source =
        File(
          'lib/features/repairs/presentation/screens/repairs_list_screen.dart',
        ).readAsStringSync();

    const statuses = <String>[
      'received',
      'diagnosed',
      'inProgress',
      'waitingPart',
      'completed',
      'delivered',
      'cancelled',
    ];
    final colors = <String>{};

    for (final status in statuses) {
      final match = RegExp(
        'RepairTicketStatus\\.$status => const Color\\((0x[0-9A-F]{8})\\)',
      ).firstMatch(source);
      expect(match, isNotNull, reason: '$status needs an explicit color');
      colors.add(match!.group(1)!);
    }

    expect(colors, hasLength(statuses.length));
    expect(source, contains('final color = _repairStatusColor(status);'));
  });
}
