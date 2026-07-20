import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const userId = 'queue-test-user';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('legacy mutations receive a stable removable identity', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'offline.mutations.$userId',
      jsonEncode([
        {
          'type': 'select_branch',
          'payload': {'branch_id': 'branch-1'},
          'created_at': '2026-07-18T12:00:00.000Z',
        },
      ]),
    );

    final firstLoad = await OfflineStore.loadMutations(userId);
    final secondLoad = await OfflineStore.loadMutations(userId);

    expect(firstLoad.single.id, startsWith('legacy-'));
    expect(secondLoad.single.id, firstLoad.single.id);

    await OfflineStore.removeMutation(
      userId: userId,
      mutationId: firstLoad.single.id,
    );

    expect(await OfflineStore.loadMutations(userId), isEmpty);
  });

  test('enqueue is preserved while another mutation is removed', () async {
    await OfflineStore.enqueueMutation(
      userId: userId,
      type: 'select_branch',
      payload: {'branch_id': 'branch-old'},
    );
    final oldMutation = (await OfflineStore.loadMutations(userId)).single;

    await Future.wait([
      OfflineStore.removeMutation(userId: userId, mutationId: oldMutation.id),
      OfflineStore.enqueueMutation(
        userId: userId,
        type: 'select_branch',
        payload: {'branch_id': 'branch-new'},
      ),
    ]);

    final remaining = await OfflineStore.loadMutations(userId);
    expect(remaining, hasLength(1));
    expect(remaining.single.payload['branch_id'], 'branch-new');
    expect(remaining.single.id, isNot(oldMutation.id));
  });

  test(
    'revoked account cleanup removes only user-scoped session cache',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline.profile.$userId', '{}');
      await prefs.setString('offline.selected_branch.$userId', 'branch-1');
      await prefs.setString('offline.mutations.$userId', '[]');
      await prefs.setString('offline.tenant.tenant-1', '{"id":"tenant-1"}');

      await OfflineStore.clearUserSessionCache(userId);

      expect(prefs.containsKey('offline.profile.$userId'), isFalse);
      expect(prefs.containsKey('offline.selected_branch.$userId'), isFalse);
      expect(prefs.containsKey('offline.mutations.$userId'), isFalse);
      expect(prefs.containsKey('offline.tenant.tenant-1'), isTrue);
    },
  );
}
