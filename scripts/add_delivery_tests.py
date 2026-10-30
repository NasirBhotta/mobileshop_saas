from pathlib import Path
p=Path('test/features/repairs/repair_financial_local_committer_test.dart')
s=p.read_text(encoding='utf-8')
s="import 'package:mobileshop_saas/core/local/local_store.dart';\nimport 'package:mobileshop_saas/core/extensions/repair_ticket_ext.dart';\n"+s
pos=s.index("  test('completion retry")
s=s[:pos]+'''  test('new completion defers stock, supplier and profit until delivery; distinct retry IDs are safe', () async {
    await _part(id: 'inventory-part',source: 'inventory',productId: 'panel',cost: 5000,sale: 8000);
    await _part(id: 'supplier-part',source: 'direct_purchase',cost: 1000,sale: 1500,
      settlementType: 'supplier_payable',supplierId: 'supplier-1');
    await RepairFinancialLocalCommitter.prepare(ticket: ticket,eventId: 'prepare',userId: 'owner',customerCharge: 10000,commission: 500);
    expect((await LocalDatabase.select("SELECT quantity FROM inventory WHERE product_id='panel'")).single['quantity'],3);
    expect(await LocalDatabase.select('SELECT * FROM repair_financial_events'),isEmpty);
    expect(await LocalDatabase.select('SELECT * FROM supplier_ledger_entries'),isEmpty);
    final restored = (await LocalStore.loadRepairTicketById(ticket.id))!;
    // Model/cache/local round trip simulates the persisted inputs used after restart.
    await LocalStore.saveRepairTicket(RepairTicketModel.fromMap(restored.toCacheMap()));
    final cached = (await LocalStore.loadRepairTicketById(ticket.id))!;
    expect(cached.deliveryAccounting,isTrue);
    expect(cached.customerCharge,10000);
    expect(cached.perJobCommission,500);
    for (final id in ['delivery-a','delivery-b']) {
      await RepairFinancialLocalCommitter.complete(ticket: cached,eventId: id,userId: 'owner',
        customerCharge: cached.customerCharge!,commission: cached.perJobCommission,atDelivery: true);
    }
    expect((await LocalDatabase.select("SELECT quantity FROM inventory WHERE product_id='panel'")).single['quantity'],2);
    final events = await LocalDatabase.select('SELECT * FROM repair_financial_events');
    expect(events,hasLength(1));
    expect(events.single['gross_profit'],3500);
    expect(await LocalDatabase.select('SELECT * FROM supplier_ledger_entries'),hasLength(1));
    final delivered = (await LocalStore.loadRepairTicketById(ticket.id))!;
    expect(delivered.status,RepairTicketStatus.delivered);
    expect(delivered.finalizedAt,isNotNull);
  });

  test('unposted completion cancellation never reverses inventory or creates profit', () async {
    await _part(id: 'inventory-part',source: 'inventory',productId: 'panel',cost: 5000,sale: 8000);
    await RepairFinancialLocalCommitter.prepare(ticket: ticket,eventId: 'prepare',userId: 'owner',customerCharge: 10000);
    await RepairFinancialLocalCommitter.cancel(ticket: ticket,eventId: 'cancel',userId: 'owner');
    expect((await LocalDatabase.select("SELECT quantity FROM inventory WHERE product_id='panel'")).single['quantity'],3);
    expect(await LocalDatabase.select('SELECT * FROM repair_financial_events'),isEmpty);
    expect((await LocalStore.loadRepairTicketById(ticket.id))!.status,RepairTicketStatus.cancelled);
  });

  test('legacy completed ticket delivery never reposts its economics', () async {
    await _part(id: 'inventory-part',source: 'inventory',productId: 'panel',cost: 5000,sale: 8000);
    await RepairFinancialLocalCommitter.complete(ticket: ticket,eventId: 'legacy-completion',userId: 'owner',customerCharge: 10000);
    await RepairFinancialLocalCommitter.complete(ticket: ticket,eventId: 'delivery',userId: 'owner',customerCharge: 10000,atDelivery: true);
    expect((await LocalDatabase.select("SELECT quantity FROM inventory WHERE product_id='panel'")).single['quantity'],2);
    expect(await LocalDatabase.select('SELECT * FROM repair_financial_events'),hasLength(1));
  });

  test('insufficient delivery stock rolls back; completion remains unposted', () async {
    await _part(id: 'inventory-part',source: 'inventory',productId: 'panel',cost: 5000,sale: 8000);
    await RepairFinancialLocalCommitter.prepare(ticket: ticket,eventId: 'prepare',userId: 'owner',customerCharge: 10000);
    await LocalDatabase.execute('UPDATE inventory SET quantity=0');
    await expectLater(RepairFinancialLocalCommitter.complete(ticket: ticket,eventId: 'delivery',userId: 'owner',customerCharge: 10000,atDelivery: true),throwsStateError);
    expect(await LocalDatabase.select('SELECT * FROM repair_financial_events'),isEmpty);
    expect((await LocalStore.loadRepairTicketById(ticket.id))!.status,RepairTicketStatus.completed);
  });

  test('completion rejects another tenant without modifying ticket', () async {
    await expectLater(RepairFinancialLocalCommitter.prepare(ticket: ticket.copyWith(tenantId:'other'),eventId: 'prepare',userId: 'owner',customerCharge: 10),throwsStateError);
    expect((await LocalStore.loadRepairTicketById(ticket.id))!.status,RepairTicketStatus.received);
  });

''' + s[pos:]
p.write_text(s,encoding='utf-8')
