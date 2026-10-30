from pathlib import Path
def edit(p,f):
 p=Path(p); p.write_text(f(p.read_text(encoding='utf-8')),encoding='utf-8')
edit('lib/features/pos/data/repositories/pos_repository.dart',lambda s:s.replace('_permissions.require(key);',"_permissions.require(key, message: 'Customer financial history permission required.');").replace("await _permissions.require(repair ? 'repair.ticket.view' : 'pos.sale.view');","await _permissions.require(repair ? 'repair.ticket.view' : 'pos.sale.view', message: 'Receipt access permission required.');"))
edit('lib/features/pos/presentation/widgets/customer_activity_panel.dart',lambda s:s.replace(".require(repair ? 'repair.ticket.view' : 'pos.sale.view');",".require(repair ? 'repair.ticket.view' : 'pos.sale.view', message: 'Receipt access permission required.');"))
def repo(s):
 a=s.index('  Future<double> _localPartCost(');b=s.index('  Future<List<RepairPaymentModel>>',a);s=s[:a]+s[b:]
 s=s.replace("    for (final ticket in tickets) {\n      await OfflineStore.saveRepairTicket(ticket);", """    final pending = await OfflineStore.loadMutations(_currentUser.id);
    final pendingIds = pending.map((m) => m.payload['ticket_id'] ??
      (m.payload['ticket'] is Map ? (m.payload['ticket'] as Map)['id'] : null)).whereType<String>().toSet();
    for (final ticket in tickets) {
      if (pendingIds.contains(ticket.id)) continue;
      await OfflineStore.saveRepairTicket(ticket);""",1)
 s=s.replace('.upsert(ticketMap, onConflict: \'id\')',".upsert(ticketMap, onConflict: 'id', ignoreDuplicates: true)")
 # Ignore-duplicates returns no row on a replay; fetch identity separately.
 a=s.index('  Future<void> _syncUpsertRepairTicket(');b=s.index('  Future<void> _syncUpdateRepairTicketStatus(',a)
 body=s[a:b]
 body=body.replace("    final data =\n        await _client\n            .from('repair_tickets')\n            .upsert(ticketMap, onConflict: 'id', ignoreDuplicates: true)\n            .select()\n            .single();", """    await _client.from('repair_tickets').upsert(ticketMap, onConflict: 'id', ignoreDuplicates: true);
    final data = await _client.from('repair_tickets').select()
      .eq('id', ticketMap['id']).eq('tenant_id', tenantId).single();""")
 s=s[:a]+body+s[b:]
 return s
edit('lib/features/repairs/data/repositories/repair_repository.dart',repo)
edit('lib/features/repairs/presentation/providers/repair_provider.dart',lambda s:s.replace('      state = AsyncData(updatedTicket);\n\n      _ref.invalidate', "      state = AsyncData(updatedTicket);\n      if (status == RepairTicketStatus.delivered) {\n        _invalidateFinancialRepair(ticket.id);\n      }\n\n      _ref.invalidate",1))
# A direct client cannot spoof the protected marker or financial finalization.
p='supabase/migrations/20261028000100_repair_delivery_accounting.sql'
def sql(s):
 s=s.replace("  if old.delivery_accounting and new.status", """  if current_user in ('authenticated','anon') and (
    new.delivery_accounting is distinct from old.delivery_accounting or
    (old.delivery_accounting and (
      new.finalized_at is distinct from old.finalized_at or
      new.customer_charge is distinct from old.customer_charge or
      new.service_charge is distinct from old.service_charge or
      new.discount_amount is distinct from old.discount_amount or
      new.per_job_commission is distinct from old.per_job_commission or
      new.other_direct_cost is distinct from old.other_direct_cost or
      new.status is distinct from old.status
    ))
  ) then raise exception 'Use the repair financial workflow.'; end if;
  if old.delivery_accounting and new.status""")
 s=s.replace('before update of status on public.repair_tickets', 'before update on public.repair_tickets')
 return s
edit(p,sql)
