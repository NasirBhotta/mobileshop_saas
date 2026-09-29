import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';
import 'package:mobileshop_saas/features/pos/data/repositories/sale_customer_resolver.dart';

void main() {
  const local = CustomerModel(
    id: 'local',
    tenantId: 'tenant',
    branchId: 'branch',
    fullName: 'Ali',
    phone: '03001234567',
  );
  late Map<String, CustomerModel> remote;
  late Map<String, String> aliases;
  late Map<String, dynamic>? pending;
  late int creates;
  Future<void> Function(Map<String, dynamic>)? onCreate;

  setUp(() {
    remote = {};
    aliases = {};
    pending = {'id': 'local'};
    creates = 0;
    onCreate = null;
  });

  SaleCustomerResolver resolver() => SaleCustomerResolver(
    resolveId: (id) async => aliases[id] ?? id,
    findRemote: (id) async => remote[id],
    loadLocal: (_) async => local,
    findByPhone:
        (phone) async =>
            remote.values.where((c) => c.phone == phone).firstOrNull,
    pendingCreation: (_) async => pending,
    createIfMissing: (data) async {
      creates++;
      if (onCreate != null) {
        await onCreate!(data);
      } else {
        remote.putIfAbsent('local', () => local);
      }
    },
    rememberAlias: (from, to) async {
      aliases[from] = to;
    },
  );

  test(
    'saved customer remains attached without replaying creation or resetting dues',
    () async {
      remote['local'] = local.copyWith(
        outstandingBalance: 800,
        creditLimit: 1000,
      );
      final result = await resolver().resolve('local');
      expect(result.id, 'local');
      expect(result.outstandingBalance, 800);
      expect(result.creditLimit, 1000);
      expect(creates, 0);
    },
  );

  test(
    'checkout waits for a newly attached customer to exist remotely',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      onCreate = (_) async {
        started.complete();
        await release.future;
        remote['local'] = local;
      };
      var resolved = false;
      final future = resolver().resolve('local').then((value) {
        resolved = true;
        return value;
      });
      await started.future;
      expect(resolved, isFalse);
      release.complete();
      expect((await future).id, 'local');
      expect(creates, 1);
    },
  );

  test(
    'saved customer with persisted alias uses the server identity',
    () async {
      aliases['local'] = 'server';
      remote['server'] = local.copyWith(id: 'server');
      expect((await resolver().resolve('local')).id, 'server');
      expect(creates, 0);
    },
  );

  test(
    'legacy phone reconciliation remembers the identity for later sales',
    () async {
      remote['server'] = local.copyWith(id: 'server', branchId: 'other-branch');
      expect((await resolver().resolve('local')).id, 'server');
      expect(aliases['local'], 'server');
      expect(creates, 0);
    },
  );

  test('concurrent background customer creation is recovered', () async {
    onCreate = (_) async {
      remote['local'] = local.copyWith(outstandingBalance: 450);
      throw StateError('duplicate insert');
    };
    expect((await resolver().resolve('local')).outstandingBalance, 450);
  });

  test(
    'phone conflict during creation resolves the winner without losing dues',
    () async {
      onCreate = (_) async {
        remote['server'] = local.copyWith(
          id: 'server',
          outstandingBalance: 900,
        );
        throw StateError('duplicate phone');
      };
      final result = await resolver().resolve('local');
      expect(result.id, 'server');
      expect(result.outstandingBalance, 900);
      expect(aliases['local'], 'server');
    },
  );

  test('network failure leaves pending creation available for retry', () async {
    onCreate = (_) async => throw TimeoutException('offline');
    await expectLater(
      resolver().resolve('local'),
      throwsA(isA<TimeoutException>()),
    );
    expect(pending, isNotNull);
    expect(remote, isEmpty);
    onCreate = null;
    expect((await resolver().resolve('local')).id, 'local');
  });

  test(
    'missing saved customer without queued creation is not silently recreated',
    () async {
      pending = null;
      await expectLater(resolver().resolve('local'), throwsStateError);
      expect(creates, 0);
    },
  );
}
