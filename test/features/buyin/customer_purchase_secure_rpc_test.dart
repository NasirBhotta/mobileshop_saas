import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/buyin/data/repositories/customer_purchase_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _userId = 'buyin-secure-test-user';
const _branchId = '22222222-2222-4222-8222-222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory databaseDirectory;
  late HttpServer server;
  late SupabaseClient client;
  late CustomerPurchaseRepository repository;
  late List<Map<String, dynamic>> rpcPayloads;
  late List<String> nonRpcPaths;
  late Future<void> Function(HttpRequest request) handleRequest;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'customer-buyin-secure-test-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return databaseDirectory.path;
          }
          return null;
        });
    await LocalDatabase.initialize();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDatabase.clearAllTables();
    await OfflineStore.clearOfflinePreferences();
    rpcPayloads = [];
    nonRpcPaths = [];
    handleRequest = (request) async {
      final body = await utf8.decoder.bind(request).join();
      if (request.uri.path != '/rest/v1/rpc/commit_customer_buyin_v2') {
        nonRpcPaths.add('${request.method} ${request.uri.path}');
        request.response.statusCode = 404;
        request.response.write(
          jsonEncode({'code': 'not_found', 'message': 'unexpected request'}),
        );
        await request.response.close();
        return;
      }
      final envelope = jsonDecode(body) as Map<String, dynamic>;
      final payload = Map<String, dynamic>.from(envelope['p_buyin'] as Map);
      rpcPayloads.add(payload);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'purchase_id': payload['id'],
          'product_id': payload['product_id'],
          'inventory_unit_id': payload['inventory_unit_id'],
          'quantity': 1,
          'duplicate': false,
        }),
      );
      await request.response.close();
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(handleRequest(request)));
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'test-key');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-session',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': _userId,
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    await OfflineStore.saveProfile(_userId, {
      'tenant_id': '11111111-1111-4111-8111-111111111111',
      'branch_id': _branchId,
    });
    repository = CustomerPurchaseRepository(client: client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    try {
      if (databaseDirectory.existsSync()) {
        databaseDirectory.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test(
    'old backend uses legacy flow only when the exact secure RPC is absent',
    () async {
      handleRequest = (request) async {
        await utf8.decoder.bind(request).join();
        if (request.uri.path == '/rest/v1/rpc/commit_customer_buyin_v2') {
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = 404;
          request.response.write(
            jsonEncode({
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.commit_customer_buyin_v2(p_buyin) in the schema cache',
            }),
          );
        } else {
          nonRpcPaths.add(request.uri.path);
          request.response.statusCode = 204;
        }
        await request.response.close();
      };

      await repository.createPurchase(
        sellerName: 'Compatibility Seller',
        sellerCnic: '00000-0000000-3',
        sellerPhone: '03000000003',
        productName: 'Compatibility phone',
        imei1: 'SECURE-IMEI-LEGACY',
        purchasePrice: 1000,
        expectedSalePrice: 1400,
      );

      expect(nonRpcPaths, contains('/rest/v1/products'));
      expect(nonRpcPaths, contains('/rest/v1/inventory'));
      expect(nonRpcPaths, contains('/rest/v1/inventory_units'));
      expect(nonRpcPaths, contains('/rest/v1/customer_purchases'));
    },
  );

  test(
    'secure success commits through one RPC and updates local cache',
    () async {
      final purchase = await repository.createPurchase(
        sellerName: 'Synthetic Seller',
        sellerCnic: '00000-0000000-0',
        sellerPhone: '03000000000',
        productName: 'Synthetic phone',
        imei1: 'SECURE-IMEI-001',
        purchasePrice: 12000,
        expectedSalePrice: 15000,
      );

      expect(rpcPayloads, hasLength(1));
      expect(rpcPayloads.single['id'], purchase.id);
      expect(rpcPayloads.single['branch_id'], _branchId);
      expect(rpcPayloads.single['create_product'], isTrue);
      expect(rpcPayloads.single['declaration_agreed'], isTrue);
      expect(nonRpcPaths, isEmpty);
      expect(
        (await OfflineStore.loadCustomerPurchases(
          _branchId,
        )).any((saved) => saved.id == purchase.id),
        isTrue,
      );
      expect(await OfflineStore.loadMutations(_userId), isEmpty);
    },
  );

  test('authorization rejection never falls back to direct writes', () async {
    handleRequest = (request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = 403;
      request.response.write(
        jsonEncode({'code': '42501', 'message': 'permission denied'}),
      );
      await request.response.close();
    };

    await expectLater(
      repository.createPurchase(
        sellerName: 'Denied Seller',
        sellerCnic: '00000-0000000-1',
        sellerPhone: '03000000001',
        productName: 'Denied phone',
        imei1: 'SECURE-IMEI-DENIED',
        purchasePrice: 100,
        expectedSalePrice: 200,
      ),
      throwsA(isA<PostgrestException>()),
    );
    expect(nonRpcPaths, isEmpty);
    expect(await OfflineStore.loadCustomerPurchases(_branchId), isEmpty);
    expect(await OfflineStore.loadMutations(_userId), isEmpty);
  });

  test(
    'timed-out request is queued and retried with the same idempotency key',
    () async {
      var requestCount = 0;
      handleRequest = (request) async {
        final body = await utf8.decoder.bind(request).join();
        final envelope = jsonDecode(body) as Map<String, dynamic>;
        final payload = Map<String, dynamic>.from(envelope['p_buyin'] as Map);
        rpcPayloads.add(payload);
        requestCount++;
        if (requestCount == 1) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'purchase_id': payload['id'],
            'product_id': payload['product_id'],
            'inventory_unit_id': payload['inventory_unit_id'],
            'quantity': requestCount > 1 ? 7 : 1,
            'duplicate': requestCount > 1,
          }),
        );
        await request.response.close();
      };

      final purchase = await repository.createPurchase(
        sellerName: 'Offline Seller',
        sellerCnic: '00000-0000000-2',
        sellerPhone: '03000000002',
        productName: 'Offline phone',
        imei1: 'SECURE-IMEI-OFFLINE',
        purchasePrice: 4000,
        expectedSalePrice: 5500,
      );
      var queued = await OfflineStore.loadMutations(_userId);
      expect(queued, hasLength(1));
      expect(queued.single.type, 'commit_customer_buyin_v2');
      expect(queued.single.payload['id'], purchase.id);

      await repository.syncOfflineMutations();

      queued = await OfflineStore.loadMutations(_userId);
      expect(queued, isEmpty);
      expect(rpcPayloads, hasLength(2));
      expect(rpcPayloads[0]['id'], rpcPayloads[1]['id']);
      expect(
        rpcPayloads[0]['inventory_unit_id'],
        rpcPayloads[1]['inventory_unit_id'],
      );
      final syncedProduct = (await OfflineStore.loadProducts(
        _branchId,
      )).singleWhere((product) => product.id == purchase.productId);
      expect(syncedProduct.stock, 7);
      expect(nonRpcPaths, isEmpty);
    },
  );
}
