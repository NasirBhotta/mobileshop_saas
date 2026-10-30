from pathlib import Path
def edit(p,f):
 p=Path(p);p.write_text(f(p.read_text(encoding='utf-8')),encoding='utf-8')
def repo(s):
 # Pending ticket work must finish in order, even during intermittent connectivity.
 pos=s.index('  Future<List<RepairPartModel>> fetchRepairParts(')
 a=s.index("    await _gate.require('repairs.tickets');",pos)+len("    await _gate.require('repairs.tickets');")
 s=s[:a]+"\n    if (await _hasPendingTicketWork(ticketId)) return _loadLocalRepairParts(ticketId);"+s[a:]
 for method in ['  Future<void> saveRepairParts(', '  Future<RepairTicketModel> cancelRepair(']:
  pos=s.index(method);a=s.index('    try {',pos)+len('    try {')
  s=s[:a]+"\n      if (await _hasPendingTicketWork(ticket.id)) {\n        throw TimeoutException('Repair parent operations are awaiting sync.');\n      }"+s[a:]
 pos=s.index('  Future<void> _commitDeferredRepair(')
 s=s[:pos]+'''  Future<bool> _hasPendingTicketWork(String ticketId) async =>
    (await OfflineStore.loadMutations(_currentUser.id)).any((m) =>
      m.payload['ticket_id'] == ticketId ||
      (m.payload['ticket'] is Map && (m.payload['ticket'] as Map)['id'] == ticketId));

''' +s[pos:]
 # Retain later local states while replaying a parent creation or earlier status.
 a=s.index('  Future<void> _syncUpsertRepairTicket(');b=s.index('  Future<void> _syncRepairPayment(',a)
 body=s[a:b]
 body=body.replace('    await OfflineStore.saveRepairTicket(savedTicket);', '''    final local = await LocalStore.loadRepairTicketById(savedTicket.id);
    if (local == null) {
      await OfflineStore.saveRepairTicket(savedTicket);
    } else {
      await OfflineStore.saveRepairTicket(local.copyWith(inventoryUnitId: savedTicket.inventoryUnitId));
    }''')
 body=body.replace('    await OfflineStore.saveRepairTicket(RepairTicketModel.fromMap(data));', '''    final remote = RepairTicketModel.fromMap(data);
    final local = await LocalStore.loadRepairTicketById(remote.id);
    if (local == null || !local.deliveryAccounting) {
      await OfflineStore.saveRepairTicket(remote);
    }''')
 s=s[:a]+body+s[b:]
 return s
edit('lib/features/repairs/data/repositories/repair_repository.dart',repo)
def local(s):
 a=s.index('  static Future<void> cancel(');b=s.index("      if (current['status'] == 'cancelled')",a)
 s=s[:b]+'''      if (current['tenant_id'] != ticket.tenantId || current['branch_id'] != ticket.branchId) {
        throw StateError('Repair scope mismatch.');
      }
'''+s[b:]
 # Delivery uses persisted inputs rather than a stale screen object after restart.
 a=s.index("      final paidRows")
 s=s[:a]+'''      if (atDelivery) {
        customerCharge = (current['customer_charge'] as num).toDouble();
        serviceCharge = (current['service_charge'] as num).toDouble();
        discount = (current['discount_amount'] as num).toDouble();
        commission = (current['per_job_commission'] as num).toDouble();
        otherDirectCost = (current['other_direct_cost'] as num).toDouble();
      }
'''+s[a:]
 return s
edit('lib/features/repairs/data/local/repair_financial_local_committer.dart',local)
edit('lib/core/constants/app_strings.dart',lambda s:s.replace('Parts are consumed and profit is finalized only after confirmation.', 'Completion records the repair charges. Stock and final profit are posted when the device is Delivered.').replace("'Gross profit: Rs ${amount.toStringAsFixed(0)}'", "'Expected gross profit: Rs ${amount.toStringAsFixed(0)}'"))
def sql(s):
 s=s.replace('public.current_user_tenant_id() <> v_ticket.tenant_id','public.current_user_tenant_id() is distinct from v_ticket.tenant_id')
 s=s.replace('  if not public.current_user_has_branch_permission(', '  if public.current_user_has_branch_permission(').replace(") then raise exception 'Not allowed.'; end if;", ") is not true then raise exception 'Not allowed.'; end if;")
 # Add customer validation only when establishing/changing a relationship.
 pos=s.rindex('commit;')
 s=s[:pos]+'''create or replace function public.validate_repair_customer_shop() returns trigger
language plpgsql set search_path = public, pg_temp as $customer$
begin
  if new.customer_id is not null and not exists (
    select 1 from public.customers where id = new.customer_id and tenant_id = new.tenant_id
  ) then raise exception using errcode = '23514', message = 'Repair customer must belong to the same shop.'; end if;
  return new;
end $customer$;
drop trigger if exists validate_repair_customer_shop on public.repair_tickets;
create trigger validate_repair_customer_shop before insert or update of customer_id,tenant_id
on public.repair_tickets for each row execute function public.validate_repair_customer_shop();
revoke all on function public.validate_repair_customer_shop() from public;
'''+s[pos:]
 return s
edit('supabase/migrations/20261028000100_repair_delivery_accounting.sql',sql)
def historysql(s):
 s=s.replace('or not public.current_user_has_branch_permission', 'or public.current_user_has_branch_permission')
 for key in ['customer.customer.view','customer.credit.view','pos.sale.view','repair.ticket.view']:
  s=s.replace("'"+key+"')", "'"+key+"') is not true")
 return s
edit('supabase/migrations/20261028000200_customer_activity.sql',historysql)
