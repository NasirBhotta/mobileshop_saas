from pathlib import Path
p=Path('lib/features/repairs/data/repositories/repair_repository.dart');s=p.read_text(encoding='utf-8')
a=s.index('  Future<void> _commitDeferredRepair(');b=s.index('  Future<void> _syncDeferredRepair(',a)
body=s[a:b]
start=body.index('        await local();');end=body.index('        return;',start)
body=body[:start]+'''        await _saveDeferredOffline(type, payload, local);
'''+body[end:]
start=body.index('    await local();',body.index('      return;')+len('      return;')) if False else -1
# Replace the pending-parent tail only.
start=body.rindex('    await local();')
body=body[:start]+'''    await _saveDeferredOffline(type, payload, local);
  }

  Future<void> _saveDeferredOffline(String type, Map<String,dynamic> payload,
    Future<void> Function() local) => LocalDatabase.runInTransaction(() async {
      await local();
      // Persist the queue before committing SQLite. A crash between these stores
      // leaves a replayable command, rather than an unqueued financial change.
      await OfflineStore.enqueueMutation(userId: _currentUser.id,type: type,payload: payload);
    });

  Future<void> _replayDeferredLocal(String type, Map<String,dynamic> payload) async {
    final ticket = await LocalStore.loadRepairTicketById(payload['ticket_id'] as String);
    if (ticket == null) throw StateError('Repair ticket is missing locally.');
    // A later queued operation may already have committed locally.
    if (ticket.status == RepairTicketStatus.cancelled || ticket.status == RepairTicketStatus.delivered) return;
    if (type == 'prepare_repair_ticket_v3') {
      await RepairFinancialLocalCommitter.prepare(ticket:ticket,
        eventId:payload['event_id'] as String,userId:_currentUser.id,
        customerCharge:(payload['customer_charge'] as num).toDouble(),
        serviceCharge:(payload['service_charge'] as num).toDouble(),
        discount:(payload['discount'] as num).toDouble(),
        commission:(payload['commission'] as num).toDouble(),
        otherDirectCost:(payload['other_direct_cost'] as num).toDouble());
    } else {
      await RepairFinancialLocalCommitter.complete(ticket:ticket,
        eventId:payload['event_id'] as String,userId:_currentUser.id,
        customerCharge:ticket.customerCharge ?? ticket.totalCost ?? 0,atDelivery:true);
    }
  }

'''
s=s[:a]+body+s[b:]
s=s.replace('            await _syncDeferredRepair(mutation.type, mutation.payload);\n            break;', '            await _syncDeferredRepair(mutation.type, mutation.payload);\n            await _replayDeferredLocal(mutation.type, mutation.payload);\n            break;',1)
anchor="        debugPrint('Repair mutation sync failed: $e');"
s=s.replace(anchor,"""        if (const {'prepare_repair_ticket_v3','deliver_repair_ticket_v3'}.contains(mutation.type) &&
            !OfflineErrorClassifier.isRetryable(e)) {
          mutation.payload['_sync_state'] = 'needs_review';
          mutation.payload['_sync_error'] = e.toString();
        }
"""+anchor,1)
p.write_text(s,encoding='utf-8')
p=Path('supabase/migrations/20261028000100_repair_delivery_accounting.sql');s=p.read_text(encoding='utf-8')
s=s.replace("v_ticket.status in ('completed','delivered') and v_ticket.delivery_accounting", "v_ticket.status in ('completed','delivered','cancelled') and v_ticket.delivery_accounting",1)
a=s.index('create or replace function public.deliver_repair_ticket_v3(')
b=s.index("  if v_ticket.status = 'delivered'",a)
s=s[:b]+'''  if exists(select 1 from public.repair_status_logs where id = p_event_id
    and ticket_id = p_ticket_id and new_status = 'delivered') then return p_event_id; end if;
'''+s[b:]
# Stable delivery log identities support interrupted replay even after cancellation.
a=s.index('create or replace function public.deliver_repair_ticket_v3(');b=s.index('create or replace function public.cancel_repair_ticket_v3(',a)
body=s[a:b].replace('insert into public.repair_status_logs(ticket_id,', 'insert into public.repair_status_logs(id,ticket_id,').replace('values(p_ticket_id,', 'values(p_event_id,p_ticket_id,')
body=body.replace('    ticket_id, tenant_id, branch_id, old_status, new_status,', '    id, ticket_id, tenant_id, branch_id, old_status, new_status,').replace('    p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, v_ticket.status,', '    p_event_id, p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, v_ticket.status,')
s=s[:a]+body+s[b:];p.write_text(s,encoding='utf-8')
