import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/repairs/data/local/repair_financial_local_committer.dart';
import 'package:mobileshop_saas/features/repairs/data/models/repair_ticket_model.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;
  const ticket = RepairTicketModel(
    id: 'ticket-1',
    tenantId: 'tenant-1',
    branchId: 'branch-1',
    customerName: 'Customer',
    deviceBrand: 'Brand',
    deviceModel: 'Model',
    faultDescription: 'Fault',
    createdBy: 'owner',
  );

  setUpAll(() async {
    databaseDirectory = Directory.systemTemp.createTempSync('repair-finance-');
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
    await LocalDatabase.execute('DELETE FROM repair_financial_events');
    await LocalDatabase.execute('DELETE FROM repair_parts');
    await LocalDatabase.execute('DELETE FROM repair_payments');
    await LocalDatabase.execute('DELETE FROM repair_tickets');
    await LocalDatabase.execute('DELETE FROM inventory');
    await LocalDatabase.execute('DELETE FROM products');
    await LocalDatabase.execute('DELETE FROM supplier_ledger_entries');
    await LocalDatabase.execute('DELETE FROM suppliers');
    await LocalDatabase.execute(
      '''
      INSERT INTO repair_tickets(
        id, tenant_id, branch_id, customer_name, device_brand, device_model,
        fault_description, status, created_by
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 'received', ?)
      ''',
      [
        ticket.id,
        ticket.tenantId,
        ticket.branchId,
        ticket.customerName,
        ticket.deviceBrand,
        ticket.deviceModel,
        ticket.faultDescription,
        ticket.createdBy,
      ],
    );
    await LocalDatabase.execute('''
      INSERT INTO products(
        id, tenant_id, branch_id, name, sale_price, cost_price
      ) VALUES ('panel', 'tenant-1', 'branch-1', 'Panel', 8000, 5000)
      ''');
    await LocalDatabase.execute(
      "INSERT INTO inventory(id, branch_id, product_id, quantity) VALUES ('inv', 'branch-1', 'panel', 3)",
    );
    await LocalDatabase.execute(
      "INSERT INTO suppliers(id, tenant_id, branch_id, name) VALUES ('supplier-1', 'tenant-1', 'branch-1', 'Supplier')",
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('completion retry consumes stock and snapshots profit once', () async {
    await _part(
      id: 'inventory-part',
      source: 'inventory',
      productId: 'panel',
      cost: 5000,
      sale: 8000,
    );
    await _part(
      id: 'direct-part',
      source: 'direct_purchase',
      cost: 1000,
      sale: 1500,
    );

    for (var i = 0; i < 2; i++) {
      await RepairFinancialLocalCommitter.complete(
        ticket: ticket,
        eventId: 'completion-1',
        userId: 'owner',
        customerCharge: 11000,
        commission: 500,
      );
    }

    final stock = await LocalDatabase.select(
      "SELECT quantity FROM inventory WHERE product_id = 'panel'",
    );
    final event = await LocalDatabase.select(
      'SELECT * FROM repair_financial_events',
    );
    expect((stock.single['quantity'] as num).toInt(), 2);
    expect(event, hasLength(1));
    expect((event.single['inventory_cost'] as num).toDouble(), 5000);
    expect((event.single['direct_parts_cost'] as num).toDouble(), 1000);
    expect((event.single['gross_profit'] as num).toDouble(), 4500);
    expect(
      await LocalDatabase.select('SELECT * FROM account_transactions'),
      isEmpty,
    );
  });

  test('completed cancellation restores stock and reverses snapshots', () async {
    await _part(
      id: 'inventory-part',
      source: 'inventory',
      productId: 'panel',
      cost: 5000,
      sale: 8000,
    );
    await _part(
      id: 'supplier-part',
      source: 'direct_purchase',
      cost: 1000,
      sale: 1500,
      settlementType: 'supplier_payable',
      supplierId: 'supplier-1',
    );
    await RepairFinancialLocalCommitter.complete(
      ticket: ticket,
      eventId: 'completion-1',
      userId: 'owner',
      customerCharge: 8000,
    );
    await RepairFinancialLocalCommitter.cancel(
      ticket: ticket,
      eventId: 'reversal-1',
      userId: 'owner',
    );

    final stock = await LocalDatabase.select(
      "SELECT quantity FROM inventory WHERE product_id = 'panel'",
    );
    final totals = await LocalDatabase.select('''
      SELECT SUM(revenue_amount) AS revenue, SUM(inventory_cost) AS cost,
        SUM(gross_profit) AS profit FROM repair_financial_events
      ''');
    expect((stock.single['quantity'] as num).toInt(), 3);
    expect((totals.single['revenue'] as num).toDouble(), 0);
    expect((totals.single['cost'] as num).toDouble(), 0);
    expect((totals.single['profit'] as num).toDouble(), 0);
    final supplier = await LocalDatabase.select(
      "SELECT outstanding_balance FROM suppliers WHERE id = 'supplier-1'",
    );
    expect((supplier.single['outstanding_balance'] as num).toDouble(), 0);
    expect(
      await LocalDatabase.select(
        "SELECT * FROM supplier_ledger_entries WHERE supplier_id = 'supplier-1'",
      ),
      hasLength(2),
    );
  });

  test('supplier-paid direct part blocks unsafe cancellation', () async {
    await _part(
      id: 'supplier-part',
      source: 'direct_purchase',
      cost: 1000,
      sale: 1500,
      settlementType: 'supplier_payable',
      supplierId: 'supplier-1',
    );
    await RepairFinancialLocalCommitter.complete(
      ticket: ticket,
      eventId: 'completion-1',
      userId: 'owner',
      customerCharge: 2000,
    );
    await LocalDatabase.execute(
      "UPDATE suppliers SET outstanding_balance = 0 WHERE id = 'supplier-1'",
    );

    await expectLater(
      RepairFinancialLocalCommitter.cancel(
        ticket: ticket,
        eventId: 'reversal-1',
        userId: 'owner',
      ),
      throwsStateError,
    );
    final status = await LocalDatabase.select(
      "SELECT status FROM repair_tickets WHERE id = 'ticket-1'",
    );
    expect(status.single['status'], 'completed');
    expect(
      await LocalDatabase.select(
        "SELECT * FROM repair_financial_events WHERE event_type = 'reversal'",
      ),
      isEmpty,
    );
  });
}

Future<void> _part({
  required String id,
  required String source,
  String? productId,
  required double cost,
  required double sale,
  String settlementType = 'already_recorded',
  String? supplierId,
}) {
  return LocalDatabase.execute(
    '''
    INSERT INTO repair_parts(
      id, tenant_id, branch_id, ticket_id, source_type, product_id, supplier_id,
      settlement_type,
      name, quantity, unit_cost_snapshot, unit_sale_price, state,
      created_by, created_at, updated_at
    ) VALUES (?, 'tenant-1', 'branch-1', 'ticket-1', ?, ?, ?, ?, 'Part', 1,
      ?, ?, 'planned', 'owner', '2026-07-28', '2026-07-28')
    ''',
    [id, source, productId, supplierId, settlementType, cost, sale],
  );
}
