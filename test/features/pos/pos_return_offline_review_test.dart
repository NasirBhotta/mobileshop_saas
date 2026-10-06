import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/authorization/permission_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/core/entitlements/supabase_entitlement_data_source.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_return_model.dart';
import 'package:mobileshop_saas/features/pos/data/repositories/pos_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const userId = 'pos-return-review-user';
  late Directory databaseDirectory;
  late HttpServer server;
  late SupabaseClient client;
  late PosRepository repository;
  late List<String> requests;

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync(
      'pos-return-review-test-',
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
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/rest/v1/sales') {
        request.response.write(
          jsonEncode({
            'id': 'return-source-sale',
            'sale_items': [
              {'id': 'source-item'},
            ],
            'sale_payments': [
              {'id': 'source-payment'},
            ],
          }),
        );
      } else if (request.uri.path == '/rest/v1/rpc/commit_pos_return_v2') {
        request.response.statusCode = 403;
        request.response.write(
          jsonEncode({'code': '42501', 'message': 'permission denied'}),
        );
      } else {
        request.response.statusCode = 404;
        request.response.write(
          jsonEncode({'code': 'not_found', 'message': 'unexpected request'}),
        );
      }
      await request.response.close();
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
    repository = PosRepository(
      client: client,
      permissions: PermissionEvaluator(
        dataSource: _TestPermissionSource(userId),
      ),
      entitlementEvaluator: EntitlementEvaluator(
        dataSource: SupabaseEntitlementDataSource(client: client),
      ),
    );
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
    'authorization rejection is retained for review without repeated RPC or direct writes',
    () async {
      await OfflineStore.enqueueMutation(
        userId: userId,
        type: 'sale_return',
        payload: {
          'id': 'pending-return-1',
          'original_sale_id': 'return-source-sale',
          'branch_id': 'branch-1',
          'user_id': userId,
          'status': 'pending_approval',
          'refund_method': 'cash',
          'refund_amount': 100,
          'refund_payment_id': 'source-payment',
          'approval_required_reason': 'Test approval',
          'created_at': '2026-10-06T00:00:00Z',
          'items': [
            {
              'product_id': 'product-1',
              'product_name': 'Test phone',
              'quantity': 1,
              'refund_amount': 100,
              'restock_product_id': 'restock-1',
              'restock_condition': 'returned',
            },
          ],
          'refund_legs': <Map<String, dynamic>>[],
        },
      );

      await repository.syncOfflineMutations();

      var queued = await OfflineStore.loadMutations(userId);
      expect(queued, hasLength(1));
      expect(queued.single.payload['_sync_state'], 'needs_review');
      expect(queued.single.payload['_sync_error_code'], '42501');
      final reviewReturn = SaleReturnModel.fromMap(queued.single.payload);
      expect(reviewReturn.syncErrorCode, '42501');
      expect(reviewReturn.toMap().containsKey('_sync_error_code'), isFalse);
      expect(
        requests.where((request) => request.contains('commit_pos_return_v2')),
        hasLength(1),
      );
      expect(
        requests.where(
          (request) =>
              request.contains('/rest/v1/sale_returns') ||
              request.contains('/rest/v1/sale_return_items') ||
              request.contains('/rest/v1/inventory'),
        ),
        isEmpty,
      );

      await repository.syncOfflineMutations();

      queued = await OfflineStore.loadMutations(userId);
      expect(queued, hasLength(1));
      expect(queued.single.payload['_sync_state'], 'needs_review');
      expect(
        requests.where((request) => request.contains('commit_pos_return_v2')),
        hasLength(1),
      );
    },
  );
}

class _TestPermissionSource implements PermissionDataSource {
  @override
  final String currentUserId;

  const _TestPermissionSource(this.currentUserId);

  @override
  Future<String?> loadTenantId(String userId) async => 'tenant-1';

  @override
  Future<List<PermissionRoleAssignment>> loadRoleAssignments({
    required String userId,
    required String tenantId,
  }) async => [];
}
