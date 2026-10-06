import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/inventory/data/sync/inventory_sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These are loopback HTTP integration tests, not widget network tests.
  HttpOverrides.global = null;
  const userId = 'queue-safety-user';
  late HttpServer server;
  late SupabaseClient client;
  late InventorySyncEngine engine;
  late List<String> requests;
  late Future<void> Function(HttpRequest) respond;

  Future<void> enqueue(String type, String id) => OfflineStore.enqueueMutation(
    userId: userId,
    type: type,
    payload:
        type == 'upsert_product'
            ? {
              'product': {
                'id': id,
                'tenant_id': 'tenant-1',
                'branch_id': 'branch-1',
                'name': id,
                'cost_price': 123.45,
                'sale_price': 456.78,
                'stock': 7,
                'reorder_threshold': 2,
              },
            }
            : {
              'product_id': id,
              'tenant_id': 'tenant-1',
              'branch_id': 'branch-1',
            },
  );

  Future<void> finish(HttpRequest request, {int status = 201}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    if (status >= 400) {
      request.response.write(
        jsonEncode({
          'code': status == 403 ? '42501' : '503',
          'message': 'Simulated upload failure',
        }),
      );
    }
    await request.response.close();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = (request) => finish(request);
    server.listen((request) async {
      requests.add(request.uri.path);
      await respond(request);
    });
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'test-key');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-session',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': userId,
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    engine = InventorySyncEngine(client: client);
    engine.hasConnection = true;
  });

  tearDown(() async {
    engine.dispose();
    await client.dispose();
    await server.close(force: true);
  });

  test('concurrent sync calls share the same worker and upload once', () async {
    await enqueue('upsert_product', 'only-once');
    final first = engine.syncNow();
    final others = List.generate(5, (_) => engine.syncNow());
    expect(others.every((sync) => identical(sync, first)), isTrue);
    await Future.wait([first, ...others]);
    expect(requests, ['/rest/v1/rpc/upsert_inventory_product_v2']);
    expect(await OfflineStore.loadMutations(userId), isEmpty);
  });

  test(
    'blank SKU and barcode in an old queue snapshot upload as null',
    () async {
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'upsert_product',
        payload: {
          'product': {
            'id': 'legacy-blank-sku',
            'tenant_id': 'tenant-1',
            'branch_id': 'branch-1',
            'name': 'repaired Mobile',
            'sku': '',
            'barcode': '   ',
            'stock': 0,
          },
        },
      );
      Map<String, dynamic>? sentBody;
      respond = (request) async {
        sentBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        await finish(request);
      };

      await engine.syncNow();

      final sentProduct = sentBody!['p_product'] as Map<String, dynamic>;
      expect(sentProduct['sku'], isNull);
      expect(sentProduct['barcode'], isNull);
      expect(await OfflineStore.loadMutations(userId), isEmpty);
    },
  );

  test(
    'worker restart resumes retained operations with original identities',
    () async {
      await enqueue('upsert_product', 'restart-pending');
      final before = (await OfflineStore.loadMutations(userId)).single;
      respond = (request) => finish(request, status: 403);
      await engine.syncNow();
      engine.dispose();
      engine = InventorySyncEngine(client: client);
      engine.hasConnection = true;
      expect((await OfflineStore.loadMutations(userId)).single.id, before.id);
      respond = (request) => finish(request);
      await engine.syncNow();
      expect(await OfflineStore.loadMutations(userId), isEmpty);
    },
  );

  test(
    'acknowledged upload leaves durable queue before the next starts',
    () async {
      await enqueue('upsert_product', 'first');
      await enqueue('upsert_product', 'second');
      var productsSeen = 0;
      respond = (request) async {
        if (request.uri.path.endsWith('/rpc/upsert_inventory_product_v2') &&
            ++productsSeen == 2) {
          final pending = await OfflineStore.loadMutations(userId);
          expect(pending, hasLength(1));
          expect(pending.single.payload['product']['id'], 'second');
          await finish(request, status: 403);
          return;
        }
        await finish(request);
      };
      await engine.syncNow();
      final retained = await OfflineStore.loadMutations(userId);
      expect(retained.single.payload['product']['id'], 'second');
      expect(engine.lastSyncError, isA<PostgrestException>());
    },
  );

  test('work added during upload drains without another trigger', () async {
    await enqueue('upsert_product', 'first');
    var added = false;
    respond = (request) async {
      if (!added) {
        added = true;
        await enqueue('upsert_product', 'new-during-upload');
      }
      await finish(request);
    };
    await engine.syncNow();
    expect(await OfflineStore.loadMutations(userId), isEmpty);
    expect(
      requests.where(
        (path) => path.endsWith('/rpc/upsert_inventory_product_v2'),
      ),
      hasLength(2),
    );
  });

  test(
    'server-unavailable response retains work and retries automatically',
    () async {
      await enqueue('upsert_product', 'retry-after-server-outage');
      final recovered = Completer<void>();
      respond = (request) async {
        if (requests.length == 1) {
          await finish(request, status: 503);
        } else {
          await finish(request);
          if (request.uri.path.endsWith('/rpc/upsert_inventory_product_v2')) {
            recovered.complete();
          }
        }
      };
      await engine.syncNow();
      expect(await OfflineStore.loadMutations(userId), hasLength(1));
      await recovered.future.timeout(const Duration(seconds: 5));
      await engine.syncNow();
      expect(await OfflineStore.loadMutations(userId), isEmpty);
      expect(engine.lastSyncError, isNull);
    },
  );

  test(
    'network failure retains failed upload and all later products',
    () async {
      await enqueue('upsert_product', 'first');
      await enqueue('upsert_product', 'second');
      await enqueue('upsert_product', 'third');
      final before = await OfflineStore.loadMutations(userId);
      // End the response before HTTP headers arrive, producing a retryable
      // connection failure rather than a database rejection.
      respond = (request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
      };

      await engine.syncNow();

      final after = await OfflineStore.loadMutations(userId);
      expect(after.map((m) => m.toMap()), before.map((m) => m.toMap()));
      expect(requests, ['/rest/v1/rpc/upsert_inventory_product_v2']);
    },
  );

  test(
    'database failure preserves payloads and dependent operations',
    () async {
      await enqueue('upsert_product', 'blocked');
      await enqueue('delete_product', 'blocked');
      final before = await OfflineStore.loadMutations(userId);
      respond = (request) => finish(request, status: 403);

      await engine.syncNow();

      expect(
        (await OfflineStore.loadMutations(userId)).map((m) => m.toMap()),
        before.map((m) => m.toMap()),
      );
      expect(requests, ['/rest/v1/rpc/upsert_inventory_product_v2']);
    },
  );

  test(
    'other modules remain queued while inventory uploads successfully',
    () async {
      for (final type in [
        'sale_checkout',
        'receive_po_goods',
        'create_expense',
      ]) {
        await enqueue(type, type);
      }
      await enqueue('upsert_product', 'product');
      final before = await OfflineStore.loadMutations(userId);

      await engine.syncNow();

      expect(
        (await OfflineStore.loadMutations(userId)).map((m) => m.toMap()),
        before.take(3).map((m) => m.toMap()),
      );
      expect(requests, ['/rest/v1/rpc/upsert_inventory_product_v2']);
    },
  );

  test(
    'secure product RPC denial retains queued work without direct-write fallback',
    () async {
      await enqueue('upsert_product', 'partial');
      await enqueue('upsert_product', 'later');
      final before = await OfflineStore.loadMutations(userId);
      respond = (request) => finish(request, status: 403);

      await engine.syncNow();

      expect(
        (await OfflineStore.loadMutations(userId)).map((m) => m.toMap()),
        before.map((m) => m.toMap()),
      );
      expect(requests, ['/rest/v1/rpc/upsert_inventory_product_v2']);
      respond = (request) => finish(request);
      await engine.syncNow();
      expect(await OfflineStore.loadMutations(userId), isEmpty);
    },
  );

  test('successful upload keeps exact product prices and stock', () async {
    await enqueue('upsert_product', 'exact-values');
    final bodies = <Map<String, dynamic>>[];
    respond = (request) async {
      bodies.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      await finish(request);
    };

    await engine.syncNow();

    final productPayload = bodies.single['p_product'] as Map<String, dynamic>;
    expect(productPayload['cost_price'], 123.45);
    expect(productPayload['sale_price'], 456.78);
    expect(productPayload['stock'], 7);
    expect(await OfflineStore.loadMutations(userId), isEmpty);
  });

  test('offline authenticated user keeps the complete queue', () async {
    await enqueue('upsert_product', 'offline');
    await enqueue('sale_checkout', 'sale');
    engine.hasConnection = false;
    await engine.syncNow();
    expect(await OfflineStore.loadMutations(userId), hasLength(2));
    expect(requests, isEmpty);
  });

  test('product queued during upload gets a follow-up pass', () async {
    await enqueue('upsert_product', 'first');
    final started = Completer<void>();
    final release = Completer<void>();
    final secondUploaded = Completer<void>();
    var inventoryUploads = 0;
    respond = (request) async {
      if (!started.isCompleted) {
        started.complete();
        await release.future;
      }
      await finish(request);
      if (request.uri.path.endsWith('/rpc/upsert_inventory_product_v2') &&
          ++inventoryUploads == 2) {
        secondUploaded.complete();
      }
    };
    final firstPass = engine.syncNow();
    await started.future.timeout(const Duration(seconds: 5));
    await enqueue('upsert_product', 'second');
    engine.triggerSync();
    release.complete();
    await firstPass;
    await secondUploaded.future.timeout(const Duration(seconds: 5));
    await engine.syncNow();
    expect(await OfflineStore.loadMutations(userId), isEmpty);
  });
}
