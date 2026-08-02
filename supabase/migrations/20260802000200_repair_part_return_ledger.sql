-- Immutable, idempotent audit ledger for parts returned by repair cancellation.
-- Price fields are copied from the completion-time snapshots; current product
-- prices can never rewrite repair history.

-- Some early deployments created repair_parts before settlement tracking was
-- introduced. CREATE TABLE IF NOT EXISTS does not add later columns, so make
-- that prerequisite explicit and idempotent here.
alter table public.repair_parts
  add column if not exists settlement_type text;

update public.repair_parts
set settlement_type = 'already_recorded'
where settlement_type is null;

alter table public.repair_parts
  alter column settlement_type set default 'already_recorded',
  alter column settlement_type set not null;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.repair_parts'::regclass
      and conname = 'repair_parts_settlement_type_check'
  ) then
    alter table public.repair_parts
      add constraint repair_parts_settlement_type_check
      check (settlement_type in ('already_recorded','supplier_payable'));
  end if;
end
$block$;

create table if not exists public.repair_part_returns (
  part_id uuid primary key
    references public.repair_parts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  ticket_id uuid not null references public.repair_tickets(id) on delete restrict,
  reversal_event_id uuid not null
    references public.repair_financial_events(id) on delete restrict,
  source_type text not null
    check (source_type in ('inventory','direct_purchase')),
  product_id uuid references public.products(id) on delete restrict,
  supplier_id uuid references public.suppliers(id) on delete restrict,
  settlement_type text not null
    check (settlement_type in ('already_recorded','supplier_payable')),
  name text not null,
  quantity integer not null check (quantity > 0),
  unit_cost_snapshot numeric(12,2) not null check (unit_cost_snapshot >= 0),
  unit_sale_price_snapshot numeric(12,2) not null
    check (unit_sale_price_snapshot >= 0),
  returned_by uuid not null references public.users(id),
  returned_at timestamptz not null default now(),
  unique (ticket_id, part_id)
);

create index if not exists repair_part_returns_ticket_idx
  on public.repair_part_returns(ticket_id, returned_at);

alter table public.repair_part_returns enable row level security;
drop policy if exists "branch users read repair part returns"
  on public.repair_part_returns;
create policy "branch users read repair part returns"
on public.repair_part_returns for select to authenticated using (
  public.current_user_has_branch_permission(
    tenant_id, branch_id, 'repair.ticket.view'
  )
);

-- Preserve audit history for cancellations completed before this migration.
insert into public.repair_part_returns(
  part_id, tenant_id, branch_id, ticket_id, reversal_event_id,
  source_type, product_id, supplier_id, settlement_type, name, quantity,
  unit_cost_snapshot, unit_sale_price_snapshot, returned_by, returned_at
)
select
  part.id, part.tenant_id, part.branch_id, part.ticket_id, reversal.id,
  part.source_type, part.product_id, part.supplier_id, part.settlement_type,
  part.name, part.quantity, part.unit_cost_snapshot, part.unit_sale_price,
  reversal.created_by, coalesce(part.reversed_at, reversal.occurred_at)
from public.repair_parts part
join lateral (
  select event.*
  from public.repair_financial_events event
  where event.ticket_id = part.ticket_id
    and event.event_type = 'reversal'
  order by event.occurred_at desc
  limit 1
) reversal on true
where part.state = 'reversed'
on conflict (part_id) do nothing;

create or replace function public.capture_repair_part_return()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if new.event_type = 'reversal' then
    insert into public.repair_part_returns(
      part_id, tenant_id, branch_id, ticket_id, reversal_event_id,
      source_type, product_id, supplier_id, settlement_type, name, quantity,
      unit_cost_snapshot, unit_sale_price_snapshot, returned_by, returned_at
    )
    select
      part.id, part.tenant_id, part.branch_id, part.ticket_id, new.id,
      part.source_type, part.product_id, part.supplier_id,
      part.settlement_type, part.name, part.quantity,
      part.unit_cost_snapshot, part.unit_sale_price,
      new.created_by, coalesce(part.reversed_at, new.occurred_at)
    from public.repair_parts part
    where part.ticket_id = new.ticket_id
      and part.state = 'reversed'
    on conflict (part_id) do nothing;
  end if;
  return new;
end
$function$;

drop trigger if exists trg_capture_repair_part_return
  on public.repair_financial_events;
create trigger trg_capture_repair_part_return
after insert on public.repair_financial_events
for each row execute function public.capture_repair_part_return();

revoke all on table public.repair_part_returns from anon;
grant select on table public.repair_part_returns to authenticated;
revoke all on function public.capture_repair_part_return() from public;
