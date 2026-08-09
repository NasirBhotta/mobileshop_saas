import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'completion status rejection is discarded only after equivalence check',
    () {
      final repository =
          File(
            'lib/features/repairs/data/repositories/repair_repository.dart',
          ).readAsStringSync();
      final completionCase = repository.indexOf(
        "case 'complete_repair_ticket_v2':",
      );
      final cancellationCase = repository.indexOf(
        "case 'cancel_repair_ticket_v2':",
        completionCase,
      );
      final body = repository.substring(completionCase, cancellationCase);

      expect(body, contains('_isCompletionStatusRejection(error)'));
      expect(body, contains('_isEquivalentCompletedRepairReplay'));
      expect(
        body,
        contains("mutation.payload['_sync_state'] = 'needs_review'"),
      );
      expect(body, contains('remaining.add(mutation)'));
      expect(body, contains('continue'));
      expect(repository, contains(".eq('event_type', 'completion')"));
      expect(repository, contains("'customer_charge'"));
      expect(repository, contains("'per_job_commission'"));
    },
  );

  test('repair mutation sync is single-flight', () {
    final repository =
        File(
          'lib/features/repairs/data/repositories/repair_repository.dart',
        ).readAsStringSync();

    expect(repository, contains('Future<void>? _offlineSyncInFlight'));
    expect(repository, contains('final activeSync = _offlineSyncInFlight'));
    expect(repository, contains('identical(_offlineSyncInFlight, sync)'));
    expect(
      repository,
      contains("mutation.payload['_sync_state'] == 'needs_review'"),
    );
  });
}
