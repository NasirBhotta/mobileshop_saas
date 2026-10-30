from pathlib import Path
root = Path(__file__).resolve().parents[1]
def read(p): return (root / p).read_text(encoding='utf-8')
def write(p, s): (root / p).write_text(s, encoding='utf-8')

base=read('supabase/migrations/20260728001500_repair_hybrid_financial_engine.sql')
start=base.index('create or replace function public.complete_repair_ticket_v2(')
end=base.index('create or replace function public.cancel_repair_ticket_v2(',start)
complete=base[start:end]
prepare=complete.replace('complete_repair_ticket_v2','prepare_repair_ticket_v3')
a=prepare.index('  for v_part in select'); b=prepare.index('  select coalesce(sum(amount),0)',a)
prepare=prepare[:a]+prepare[b:]
a=prepare.index('  v_profit :='); b=prepare.index('  update public.repair_tickets set',a)
prepare=prepare[:a]+prepare[b:]
prepare=prepare.replace('    parts_cost = v_inventory_cost + v_direct_cost,','    delivery_accounting = true,')
prepare=prepare.replace('completed_at = now(), finalized_at = now(), updated_at = now()', 'completed_at = now(), updated_at = now()')
a=prepare.index('  if exists ('); b=prepare.index("  if v_ticket.status in",a)
prepare=prepare[:a]+'''  if v_ticket.status in ('completed','delivered') and v_ticket.delivery_accounting
    and v_ticket.customer_charge is not distinct from p_customer_charge
    and v_ticket.service_charge = coalesce(p_service_charge,0)
    and v_ticket.discount_amount = coalesce(p_discount,0)
    and v_ticket.per_job_commission = coalesce(p_commission,0)
    and v_ticket.other_direct_cost = coalesce(p_other_direct_cost,0)
  then return p_event_id; end if;
'''+prepare[b:]
delivery=complete.replace('complete_repair_ticket_v2','deliver_repair_ticket_v3')
a=delivery.index('  p_ticket_id uuid,'); b=delivery.index(') returns uuid',a)
delivery=delivery[:a]+'  p_ticket_id uuid, p_event_id uuid\n'+delivery[b:]
delivery=delivery.replace('  v_ticket public.repair_tickets%rowtype;', '''  v_ticket public.repair_tickets%rowtype;
  p_customer_charge numeric; p_service_charge numeric; p_discount numeric;
  p_commission numeric; p_other_direct_cost numeric;''',1)
a=delivery.index('  if exists ('); b=delivery.index('  if p_customer_charge is null',a)
delivery=delivery[:a]+'''  if v_ticket.status = 'delivered' then return p_event_id; end if;
  if v_ticket.status <> 'completed' then
    raise exception 'Only completed tickets may be delivered.';
  end if;
  -- Historical completion postings are immutable: only hand over the device.
  if not v_ticket.delivery_accounting or v_ticket.finalized_at is not null or exists (
    select 1 from public.repair_financial_events
    where ticket_id = p_ticket_id and event_type = 'completion'
  ) then
    update public.repair_tickets set status = 'delivered', delivered_at = now(), updated_at = now()
    where id = p_ticket_id;
    insert into public.repair_status_logs(ticket_id, tenant_id, branch_id, old_status, new_status, changed_by)
    values(p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, 'completed', 'delivered', auth.uid());
    return p_event_id;
  end if;
  p_customer_charge := v_ticket.customer_charge;
  p_service_charge := v_ticket.service_charge; p_discount := v_ticket.discount_amount;
  p_commission := v_ticket.per_job_commission; p_other_direct_cost := v_ticket.other_direct_cost;
'''+delivery[b:]
delivery=delivery.replace("status = 'completed'", "status = 'delivered'")
delivery=delivery.replace('completed_at = now(), finalized_at = now(), updated_at = now()', 'delivered_at = now(), finalized_at = now(), updated_at = now()')
delivery=delivery.replace("    'completed', auth.uid(), 'Repair financial completion'", "    'delivered', auth.uid(), 'Repair financial delivery'")
cancel=read('supabase/migrations/20260729000200_atomic_paid_repair_cancellation.sql')
a=cancel.index('create or replace function public.cancel_repair_ticket_v3('); b=cancel.index('$function$;',a)+len('$function$;')
cancel=cancel[a:b].replace("  if v_ticket.status in ('completed','delivered') then", "  if v_ticket.status in ('completed','delivered') and (\n    not v_ticket.delivery_accounting or v_ticket.finalized_at is not null or exists (\n      select 1 from public.repair_financial_events where ticket_id = p_ticket_id and event_type = 'completion'\n    )\n  ) then")
sql='''-- Additive rollout: preserve legacy v2 RPC semantics and every historical posting.
begin;
alter table public.repair_tickets
  add column if not exists delivery_accounting boolean not null default false;
'''+prepare+delivery+cancel+'''
revoke all on function public.prepare_repair_ticket_v3(uuid,uuid,numeric,numeric,numeric,numeric,numeric) from public;
grant execute on function public.prepare_repair_ticket_v3(uuid,uuid,numeric,numeric,numeric,numeric,numeric) to authenticated;
revoke all on function public.deliver_repair_ticket_v3(uuid,uuid) from public;
grant execute on function public.deliver_repair_ticket_v3(uuid,uuid) to authenticated;

-- Prevent generic status updates from bypassing the new delivery transaction.
-- RPC-owned posting sets finalized_at together with status under the same lock.
create or replace function public.guard_deferred_repair_delivery() returns trigger
language plpgsql set search_path = public, pg_temp as $guard$
begin
  if old.delivery_accounting and new.status = 'delivered' and old.status <> 'delivered'
    and new.finalized_at is null and not exists (
      select 1 from public.repair_financial_events where ticket_id = old.id and event_type = 'completion'
    ) then raise exception 'Use the repair delivery workflow.'; end if;
  return new;
end $guard$;
drop trigger if exists guard_deferred_repair_delivery on public.repair_tickets;
create trigger guard_deferred_repair_delivery before update of status on public.repair_tickets
for each row execute function public.guard_deferred_repair_delivery();
revoke all on function public.guard_deferred_repair_delivery() from public;
commit;
'''
write('supabase/migrations/20261028000100_repair_delivery_accounting.sql',sql)

