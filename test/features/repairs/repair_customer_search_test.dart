import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repair customer search is debounced and keeps current results', () {
    final screen =
        File(
          'lib/features/repairs/presentation/screens/repairs_list_screen.dart',
        ).readAsStringSync();

    expect(screen, contains('Duration(milliseconds: 250)'));
    expect(screen, contains('Customer name se repair search karein'));
    expect(screen, contains('ticketsAsync.isLoading && _lastTickets != null'));
  });

  test('customer query reaches remote and offline repair searches', () {
    final repository =
        File(
          'lib/features/repairs/data/repositories/repair_repository.dart',
        ).readAsStringSync();
    final localStore =
        File('lib/core/local/local_store.dart').readAsStringSync();
    final offlineStore =
        File('lib/core/offline/offline_store.dart').readAsStringSync();

    expect(repository, contains("ilike('customer_name'"));
    expect(localStore, contains('customer_name LIKE ?'));
    expect(
      offlineStore,
      contains('ticket.customerName.toLowerCase().contains(normalizedQuery)'),
    );
  });
}
