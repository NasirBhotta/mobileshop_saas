import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/features/pos/data/local/customer_activity_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    final directory = Directory.systemTemp.createTempSync('customer-activity-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'getApplicationSupportDirectory'
                  ? directory.path
                  : null,
        );
    await LocalDatabase.initialize();
    await LocalDatabase.execute(
      "INSERT INTO customers(id,tenant_id,branch_id,full_name) VALUES('customer','tenant','branch','Ali')",
    );
    for (var i = 0; i < 27; i++) {
      await LocalDatabase.execute(
        "INSERT INTO sales(id,branch_id,customer_id,user_id,total,created_at) VALUES(?,'branch','customer','owner',100,'2026-10-10T12:00:00Z')",
        ['sale-$i'],
      );
      await LocalDatabase.execute(
        "INSERT INTO sale_payments(id,sale_id,method,amount) VALUES(?,?,'cash',60)",
        ['cash-$i', 'sale-$i'],
      );
      await LocalDatabase.execute(
        "INSERT INTO sale_payments(id,sale_id,method,amount) VALUES(?,?,'credit',40)",
        ['credit-$i', 'sale-$i'],
      );
    }
    await LocalDatabase.execute(
      "INSERT INTO customer_settlements(id,customer_id,branch_id,user_id,amount,method,created_at) VALUES('settlement','customer','branch','owner',50,'cash','2026-10-11T12:00:00Z')",
    );
    await LocalDatabase.execute(
      "INSERT INTO repair_tickets(id,tenant_id,branch_id,customer_id,customer_name,device_brand,device_model,fault_description,status,created_by,customer_charge,created_at) VALUES('repair','tenant','branch','customer','Ali','Phone','Model','Fault','completed','owner',200,'2026-10-15T12:00:00Z')",
    );
    await LocalDatabase.execute(
      "INSERT INTO repair_payments(id,tenant_id,branch_id,ticket_id,amount,method,account_id,ledger_transaction_id,received_by,received_at,created_at) VALUES('payment','tenant','branch','repair',80,'cash','account','ledger','owner','2026-10-16T12:00:00Z','2026-10-16T12:00:00Z')",
    );
    // Guests and other branches do not leak into a registered customer's history.
    await LocalDatabase.execute(
      "INSERT INTO sales(id,branch_id,user_id,total,created_at) VALUES('guest','branch','owner',9999,'2026-10-10')",
    );
    await LocalDatabase.execute(
      "INSERT INTO sales(id,branch_id,customer_id,user_id,total,created_at) VALUES('other','other-branch','customer','owner',9999,'2026-10-10')",
    );
  });

  test(
    'offline totals cover all pages, exclude khata from cash, and count visits once',
    () async {
      final page = await CustomerActivityLocalStore.load(
        tenantId: 'tenant',
        branchId: 'branch',
        customerId: 'customer',
        from: DateTime.utc(2026, 10),
        to: DateTime.utc(2026, 11),
      );
      expect(page.cached, isTrue);
      expect(page.entries, hasLength(25));
      expect(page.count, 28);
      expect(page.amount('visits'), 28);
      expect(page.amount('purchase_amount'), 2700);
      expect(page.amount('payments'), 1750);
      expect(page.amount('repair_balance'), 120);
      final next = await CustomerActivityLocalStore.load(
        tenantId: 'tenant',
        branchId: 'branch',
        customerId: 'customer',
        offset: 25,
      );
      expect(next.entries, hasLength(3));
      expect(next.amount('purchase_amount'), 2700);
    },
  );
  test('date range and tenant isolation apply to every aggregate', () async {
    final range = await CustomerActivityLocalStore.load(
      tenantId: 'tenant',
      branchId: 'branch',
      customerId: 'customer',
      from: DateTime.utc(2026, 10, 15),
      to: DateTime.utc(2026, 10, 17),
    );
    expect(range.count, 1);
    expect(range.amount('payments'), 80);
    final other = await CustomerActivityLocalStore.load(
      tenantId: 'other',
      branchId: 'branch',
      customerId: 'customer',
    );
    expect(other.entries, isEmpty);
    expect(other.amount('purchase_amount'), 0);
    expect(other.amount('payments'), 0);
  });
  test(
    'customer and transaction edits never add visits or change historical amounts',
    () async {
      await LocalDatabase.execute(
        "UPDATE customers SET full_name='New name' WHERE id='customer'",
      );
      await LocalDatabase.execute(
        "UPDATE sales SET notes='edited' WHERE customer_id='customer'",
      );
      final page = await CustomerActivityLocalStore.load(
        tenantId: 'tenant',
        branchId: 'branch',
        customerId: 'customer',
      );
      expect(page.amount('visits'), 28);
      expect(page.amount('purchase_amount'), 2700);
    },
  );
}
