import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/core/offline/offline_store.dart';
import 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';
import 'package:mobileshop_saas/core/entitlements/entitlement_evaluator.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';
import 'package:mobileshop_saas/features/repairs/data/repositories/repair_repository.dart';
import 'package:mobileshop_saas/features/pos/data/models/customer_model.dart';
import 'package:mobileshop_saas/features/onboarding/data/models/shop_setup_model.dart';

class Features extends Fake implements EntitlementDataSource {
  @override
  String? get currentUserId => 'user';
  @override
  Future<TenantEntitlementContext?> loadTenantContext(String id) async =>
      const TenantEntitlementContext(
        tenantId: 'tenant',
        compatibilityPlanKey: 'enterprise',
      );
  @override
  Future<TenantEntitlementSnapshot> loadSnapshot(String id) async =>
      const TenantEntitlementSnapshot(
        subscriptionPlanKey: 'test',
        planFeatures: [
          EntitlementFeatureValue(key: 'repairs.tickets', enabled: true),
        ],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const ticket = RepairTicketModel(
    id: 'ticket',
    tenantId: 'tenant',
    branchId: 'branch',
    customerName: 'Guest',
    deviceBrand: 'Phone',
    deviceModel: 'Model',
    faultDescription: 'Screen',
    createdBy: 'user',
  );
  late HttpServer server;
  late SupabaseClient client;
  late List<String> calls;
  var failDelivery = false;
  var denyPrepare = false;
  var offline = false;
  RepairRepository repository() => RepairRepository(
    client: client,
    entitlementEvaluator: EntitlementEvaluator(dataSource: Features()),
  );
  setUpAll(() async {
    final directory = Directory.systemTemp.createTempSync(
      'repair-delivery-sync-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              call.method == 'getApplicationSupportDirectory'
                  ? directory.path
                  : null,
        );
    await LocalDatabase.initialize();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (final table in [
      'repair_parts',
      'repair_financial_events',
      'repair_status_logs',
      'repair_tickets',
      'inventory',
    ]) {
      await LocalDatabase.execute('DELETE FROM $table');
    }
    await LocalStore.saveRepairTicket(ticket);
    await LocalDatabase.execute(
      "INSERT INTO inventory(id,branch_id,product_id,quantity) VALUES('stock','branch','screen',5)",
    );
    await LocalDatabase.execute(
      "INSERT INTO repair_parts(id,tenant_id,branch_id,ticket_id,source_type,product_id,name,quantity,unit_cost_snapshot,unit_sale_price,state,created_by,created_at,updated_at) VALUES('part','tenant','branch','ticket','inventory','screen','Screen',1,40,100,'planned','user','2026-10-28','2026-10-28')",
    );
    calls = [];
    failDelivery = false;
    denyPrepare = false;
    offline = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final type = request.uri.path.split('/').last;
      await utf8.decoder.bind(request).join();
      calls.add(type);
      if (offline) {
        final socket = await request.response.detachSocket();
        socket.destroy();
        return;
      }
      if (type == 'deliver_repair_ticket_v3' && failDelivery) {
        final socket = await request.response.detachSocket();
        socket.destroy();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      if (type == 'prepare_repair_ticket_v3' && denyPrepare) {
        request.response.statusCode = 400;
        request.response.write(
          jsonEncode({
            'code': '23514',
            'message': 'Simulated financial conflict',
          }),
        );
      } else {
        request.response.write(jsonEncode('event'));
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
          'id': 'user',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'offline completion and delivery survive repository restart and interrupted reconnect without duplicate stock/profit',
    () async {
      await OfflineStore.enqueueMutation(
        userId: 'user',
        type: 'save_repair_parts_v2',
        payload: {'ticket_id': 'ticket', 'parts': []},
      );
      final repo = repository();
      final completed = await repo.completeRepair(
        ticket: ticket,
        customerCharge: 100,
        commission: 10,
      );
      expect(calls, isEmpty);
      expect(
        await LocalDatabase.select('SELECT * FROM repair_financial_events'),
        isEmpty,
      );
      final delivered = await repo.updateRepairTicketStatus(
        ticket: completed,
        status: RepairTicketStatus.delivered,
      );
      expect(delivered.status, RepairTicketStatus.delivered);
      expect(
        (await LocalDatabase.select(
          'SELECT quantity FROM inventory',
        )).single['quantity'],
        4,
      );
      failDelivery = true;
      await repo.syncOfflineMutations();
      final pending = await OfflineStore.loadMutations('user');
      expect(pending.map((m) => m.type), ['deliver_repair_ticket_v3']);
      failDelivery = false;
      final restarted = repository();
      await Future.wait([
        restarted.syncOfflineMutations(),
        restarted.syncOfflineMutations(),
      ]);
      await restarted.syncOfflineMutations();
      expect(await OfflineStore.loadMutations('user'), isEmpty);
      expect(calls, [
        'save_repair_parts_v2',
        'prepare_repair_ticket_v3',
        'deliver_repair_ticket_v3',
        'deliver_repair_ticket_v3',
      ]);
      expect(
        (await LocalDatabase.select(
          'SELECT quantity FROM inventory',
        )).single['quantity'],
        4,
      );
      expect(
        await LocalDatabase.select('SELECT * FROM repair_financial_events'),
        hasLength(1),
      );
      expect(
        (await LocalStore.loadRepairTicketById('ticket'))!.status,
        RepairTicketStatus.delivered,
      );
    },
  );

  test(
    'permanent completion conflict retains review metadata and blocks dependent delivery',
    () async {
      await OfflineStore.enqueueMutation(
        userId: 'user',
        type: 'prepare_repair_ticket_v3',
        payload: {
          'ticket_id': 'ticket',
          'event_id': 'prep',
          'customer_charge': 100,
          'service_charge': 0,
          'discount': 0,
          'commission': 0,
          'other_direct_cost': 0,
        },
      );
      await OfflineStore.enqueueMutation(
        userId: 'user',
        type: 'deliver_repair_ticket_v3',
        payload: {'ticket_id': 'ticket', 'event_id': 'delivery'},
      );
      denyPrepare = true;
      final repo = repository();
      await repo.syncOfflineMutations();
      await repo.syncOfflineMutations();
      final pending = await OfflineStore.loadMutations('user');
      expect(pending, hasLength(2));
      expect(pending.first.payload['_sync_state'], 'needs_review');
      expect(calls, ['prepare_repair_ticket_v3']);
      expect(
        await LocalDatabase.select('SELECT * FROM repair_financial_events'),
        isEmpty,
      );
    },
  );

  test(
    'queue persisted before SQLite commit can recover local effects after restart',
    () async {
      await OfflineStore.enqueueMutation(
        userId: 'user',
        type: 'prepare_repair_ticket_v3',
        payload: {
          'ticket_id': 'ticket',
          'event_id': 'prep',
          'customer_charge': 100,
          'service_charge': 0,
          'discount': 0,
          'commission': 10,
          'other_direct_cost': 0,
        },
      );
      await OfflineStore.enqueueMutation(
        userId: 'user',
        type: 'deliver_repair_ticket_v3',
        payload: {'ticket_id': 'ticket', 'event_id': 'delivery'},
      );
      await repository().syncOfflineMutations();
      expect(await OfflineStore.loadMutations('user'), isEmpty);
      expect(
        (await LocalStore.loadRepairTicketById('ticket'))!.status,
        RepairTicketStatus.delivered,
      );
      expect(
        (await LocalDatabase.select(
          'SELECT quantity FROM inventory',
        )).single['quantity'],
        4,
      );
      expect(
        (await LocalDatabase.select(
          'SELECT gross_profit FROM repair_financial_events',
        )).single['gross_profit'],
        50,
      );
    },
  );

  test(
    'offline registered and guest ticket creation preserves IDs without creating duplicate customers',
    () async {
      offline = true;
      await OfflineStore.saveProfile('user', {
        'id': 'user',
        'tenant_id': 'tenant',
        'branch_id': 'branch',
      });
      await OfflineStore.saveBranches('tenant', [
        const BranchInputModel(id: 'branch', name: 'Test'),
      ]);
      const customer = CustomerModel(
        id: 'new-customer',
        tenantId: 'tenant',
        branchId: 'branch',
        fullName: 'Ali',
        phone: '0300',
      );
      await OfflineStore.saveCustomer(customer);
      await OfflineStore.enqueueMutation(
        userId: 'user',
        type: 'add_customer',
        payload: {
          'id': 'new-customer',
          'tenant_id': 'tenant',
          'branch_id': 'branch',
          'full_name': 'Ali',
          'phone': '0300',
        },
      );
      final repo = repository();
      final linked = await repo.createRepairTicket(
        customerId: 'new-customer',
        customerName: 'Ali',
        customerPhone: '0300',
        deviceBrand: 'Phone',
        deviceModel: 'Model',
        faultDescription: 'Fault',
      );
      final guest = await repo.createRepairTicket(
        customerName: 'Guest',
        deviceBrand: 'Phone',
        deviceModel: 'Model',
        faultDescription: 'Fault',
      );
      expect(linked.customerId, 'new-customer');
      expect(guest.customerId, isNull);
      expect(
        (await LocalStore.loadRepairTicketById(linked.id))!.customerId,
        'new-customer',
      );
      expect(
        await LocalDatabase.select(
          "SELECT * FROM customers WHERE id='new-customer'",
        ),
        hasLength(1),
      );
      final pending = await OfflineStore.loadMutations('user');
      expect(pending.where((m) => m.type == 'add_customer'), hasLength(1));
      expect(
        pending.where((m) => m.type == 'upsert_repair_ticket'),
        hasLength(2),
      );
    },
  );
}
