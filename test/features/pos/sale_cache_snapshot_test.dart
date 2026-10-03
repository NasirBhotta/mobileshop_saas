import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshop_saas/core/local/local_database.dart';
import 'package:mobileshop_saas/core/local/local_store.dart';
import 'package:mobileshop_saas/features/pos/data/models/cart_item_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_model.dart';
import 'package:mobileshop_saas/features/pos/data/models/sale_payment_model.dart';
import 'package:mobileshop_saas/features/pos/data/services/receipt_service.dart';
import 'package:mobileshop_saas/features/reports/data/local/sales_report_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    final directory = Directory.systemTemp.createTempSync('sale-cache-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => directory.path);
    await LocalDatabase.initialize();
    await LocalDatabase.execute(
      "INSERT INTO branches(id, tenant_id, name, address, city) VALUES('branch', 'tenant', 'Shop', '', '')",
    );
  });
  setUp(() async {
    await LocalDatabase.execute('DELETE FROM sale_items');
    await LocalDatabase.execute('DELETE FROM sale_payments');
    await LocalDatabase.execute('DELETE FROM sales');
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  SaleModel sale({bool tracked = true, bool twoPhones = false}) => SaleModel(
    id: 'sale',
    branchId: 'branch',
    userId: 'cashier',
    subtotal: twoPhones ? 88000 : 44000,
    discountAmount: 0,
    taxAmount: 0,
    total: twoPhones ? 88000 : 44000,
    items: [
      CartItemModel(
        productId: 'phone',
        productName: 'Samsung A17 5G',
        unitPrice: 44000,
        imei: tracked ? '356892110293847' : null,
        deviceDetails: tracked ? 'Black' : null,
        unitId: tracked ? 'unit-1' : null,
      ),
      if (twoPhones)
        const CartItemModel(
          productId: 'phone',
          productName: 'Samsung A17 5G',
          unitPrice: 44000,
          imei: '356892110293855',
          unitId: 'unit-2',
        ),
      const CartItemModel(
        productId: 'cable',
        productName: 'C to C Cable',
        unitPrice: 0,
      ),
    ],
    payments: const [
      SalePaymentModel(
        id: 'payment',
        method: PaymentMethod.cash,
        amount: 44000,
      ),
    ],
  );

  test(
    'local reprint and repeated caching retain IMEI without duplicating phone',
    () async {
      await LocalStore.saveSale(sale());
      for (var retry = 0; retry < 3; retry++) {
        final loaded = (await LocalStore.loadSales('branch')).single;
        expect(loaded.items, hasLength(2));
        final phone = loaded.items.firstWhere(
          (item) => item.productId == 'phone',
        );
        expect(phone.imei, '356892110293847');
        expect(phone.deviceDetails, 'Black');
        expect(phone.unitId, 'unit-1');
        final receipt = ReceiptService.formatReceipt(sale: loaded);
        expect('Samsung A17 5G'.allMatches(receipt), hasLength(1));
        expect(receipt, contains('IMEI: 356892110293847'));
        expect(receipt, contains('Total Qty: 2'));
        await LocalStore.saveSale(loaded);
      }
    },
  );

  test(
    'authoritative refresh removes stale cached row with a different IMEI key',
    () async {
      await LocalStore.saveSale(sale());
      await LocalStore.saveSale(sale(tracked: false));
      final loaded = (await LocalStore.loadSales('branch')).single;
      expect(loaded.items, hasLength(2));
      expect(loaded.total, 44000);
      expect(
        'Samsung A17 5G'.allMatches(ReceiptService.formatReceipt(sale: loaded)),
        hasLength(1),
      );
    },
  );

  test('two real phones with different IMEIs remain separate rows', () async {
    await LocalStore.saveSale(sale(twoPhones: true));
    await LocalStore.saveSale(sale(twoPhones: true));
    final loaded = (await LocalStore.loadSales('branch')).single;
    expect(loaded.items, hasLength(3));
    expect(
      loaded.items
          .where((item) => item.productId == 'phone')
          .map((item) => item.imei),
      unorderedEquals(['356892110293847', '356892110293855']),
    );
  });

  test('failed refresh rolls back the previous sale snapshot', () async {
    await LocalStore.saveSale(sale());
    await LocalDatabase.execute('''
      CREATE TRIGGER reject_cache_refresh BEFORE INSERT ON sale_items
      BEGIN SELECT RAISE(ABORT, 'simulated cache failure'); END
    ''');
    try {
      await expectLater(
        LocalStore.saveSale(sale(tracked: false)),
        throwsA(anything),
      );
      final loaded = (await LocalStore.loadSales('branch')).single;
      expect(loaded.items, hasLength(2));
      expect(
        loaded.items.firstWhere((item) => item.productId == 'phone').imei,
        '356892110293847',
      );
    } finally {
      await LocalDatabase.execute('DROP TRIGGER reject_cache_refresh');
    }
  });

  test(
    'server migration changes only sold-unit metadata in the commit function',
    () {
      final previous = File(
        'supabase/migrations/20260725000700_mobile_services_realtime_and_pos_uuid_compat.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final migration = File(
        'supabase/migrations/20261003000100_preserve_sale_item_imei.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      const marker = 'create or replace function public.commit_pos_sale(';
      final restored = migration
          .substring(migration.indexOf(marker))
          .replaceFirst(
            '    cogs_total, line_total, imei, device_details, unit_id\n',
            '    cogs_total, line_total\n',
          )
          .replaceFirst(
            "    (value->>'line_total')::numeric,\n    nullif(btrim(value->>'imei'), ''),\n    nullif(btrim(value->>'device_details'), ''),\n    nullif(btrim(value->>'unit_id'), '')",
            "    (value->>'line_total')::numeric",
          );
      expect(restored, previous.substring(previous.indexOf(marker)));
    },
  );

  test(
    'sale cache refresh keeps report profit and local day unchanged',
    () async {
      final instant = DateTime.parse('2026-10-03T20:32:17+05:00');
      final local = instant.toLocal();
      final receipt = SaleModel(
        id: 'sale',
        branchId: 'branch',
        userId: 'cashier',
        subtotal: 52200,
        discountAmount: 0,
        taxAmount: 0,
        total: 52200,
        createdAt: local,
        items: const [
          CartItemModel(
            productId: 'phone',
            productName: 'Phone',
            unitPrice: 52200,
            unitCost: 48545,
            imei: '356892110293847',
          ),
        ],
      );
      Future<double> profit() async =>
          (await SalesReportLocalStore.buildLocalReport(
            tenantId: 'tenant',
            branchId: 'branch',
            dateFrom: local,
            dateTo: local,
          )).summary.grossProfit;
      await LocalStore.saveSale(receipt);
      expect(await profit(), 3655);
      final remote = SaleModel.fromMap({
        'id': 'sale',
        'branch_id': 'branch',
        'user_id': 'cashier',
        'status': 'completed',
        'subtotal': 52200,
        'discount_amount': 0,
        'tax_amount': 0,
        'total': 52200,
        'created_at': instant.toUtc().toIso8601String(),
        'sale_items': receipt.items.map((item) => item.toMap()).toList(),
      });
      await LocalStore.saveSale(remote);
      final loaded = (await LocalStore.loadSales('branch')).single;
      expect(loaded.createdAt, local);
      expect(loaded.createdAt!.day, local.day);
      expect(await profit(), 3655);
      // The dashboard uses sale headers, but profit uses item rows. A stale
      // item can inflate profit while the sales total remains unchanged.
      await LocalDatabase.execute(
        "INSERT INTO sale_items(id, sale_id, product_id, product_name, quantity, unit_price, cogs_total, line_total) VALUES('stale', 'sale', 'cable', 'Stale item', 1, 3200, 0, 3200)",
      );
      expect((await LocalStore.loadSales('branch')).single.total, 52200);
      expect(await profit(), 6855);
      await LocalStore.saveSale(remote);
      expect(await profit(), 3655);
    },
  );
}
