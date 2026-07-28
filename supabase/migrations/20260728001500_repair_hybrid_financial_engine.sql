-- Hybrid repair parts and immutable completion/reversal snapshots.

alter table public.repair_tickets
  add column if not exists customer_charge numeric(12,2),
  add column if not exists service_charge numeric(12,2) not null default 0,
  add column if not exists discount_amount numeric(12,2) not null default 0,
  add column if not exists per_job_commission numeric(12,2) not null default 0,
  add column if not exists other_direct_cost numeric(12,2) not null default 0,
  add column if not exists finalized_at timestamptz,
  add column if not exists reversed_at timestamptz,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references public.users(id);

create table if not exists public.repair_parts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  ticket_id uuid not null references public.repair_tickets(id) on delete restrict,
  source_type text not null check (source_type in ('inventory','direct_purchase')),
  product_id uuid references public.products(id) on delete restrict,
  supplier_id uuid references public.suppliers(id) on delete restrict,
  settlement_type text not null default 'already_recorded'
    check (settlement_type in ('already_recorded','supplier_payable')),
  name text not null,
  quantity integer not null check (quantity > 0),
  unit_cost_snapshot numeric(12,2) not null check (unit_cost_snapshot >= 0),
  unit_sale_price numeric(12,2) not null check (unit_sale_price >= 0),
  state text not null default 'planned'
    check (state in ('planned','consumed','reversed')),
  consumed_at timestamptz,
  reversed_at timestamptz,
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (source_type = 'inventory' and product_id is not null)
    or source_type = 'direct_purchase'
  )
);

create table if not exists public.repair_financial_events (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  ticket_id uuid not null references public.repair_tickets(id) on delete restrict,
  event_type text not null check (event_type in ('completion','reversal')),
  source_event_key text not null,
  revenue_amount numeric(12,2) not null,
  inventory_cost numeric(12,2) not null,
  direct_parts_cost numeric(12,2) not null,
  commission_cost numeric(12,2) not null,
  other_direct_cost numeric(12,2) not null,
  gross_profit numeric(12,2) not null,
  reversal_of_event_id uuid references public.repair_financial_events(id),
  occurred_at timestamptz not null,
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  unique (tenant_id, branch_id, source_event_key)
);

create index if not exists repair_parts_ticket_idx
  on public.repair_parts(ticket_id, state);
create index if not exists repair_financial_events_ticket_idx
  on public.repair_financial_events(ticket_id, occurred_at);

alter table public.repair_parts enable row level security;
alter table public.repair_financial_events enable row level security;

-- A migration may be retried after a later statement fails. PostgreSQL does not
-- support CREATE POLICY IF NOT EXISTS, so replace these policies explicitly.
drop policy if exists "branch users read repair parts"
  on public.repair_parts;
create policy "branch users read repair parts" on public.repair_parts
for select to authenticated using (
  public.current_user_has_branch_permission(
    tenant_id, branch_id, 'repair.ticket.view'
  )
);

drop policy if exists "branch users read repair financial events"
  on public.repair_financial_events;
create policy "branch users read repair financial events"
on public.repair_financial_events for select to authenticated using (
  public.current_user_has_branch_permission(
    tenant_id, branch_id, 'repair.ticket.view'
  )
);

create or replace function public.save_repair_parts_v2(
  p_ticket_id uuid, p_parts jsonb
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_ticket public.repair_tickets%rowtype;
  v_part record;
  v_product public.products%rowtype;
begin
  select * into v_ticket from public.repair_tickets
  where id = p_ticket_id for update;
  if not found then raise exception 'Repair ticket not found.'; end if;
  if public.current_user_tenant_id() <> v_ticket.tenant_id or
     not public.current_user_has_branch_permission(
       v_ticket.tenant_id, v_ticket.branch_id, 'repair.ticket.update'
     ) then raise exception 'Not allowed.'; end if;
  if v_ticket.status in ('completed','delivered') then
    if (select count(*) from public.repair_parts
        where ticket_id = p_ticket_id) = jsonb_array_length(p_parts)
       and not exists (
         select 1 from jsonb_to_recordset(p_parts) as requested(
           id uuid, source_type text, product_id uuid, supplier_id uuid,
           settlement_type text, name text, quantity integer,
           unit_cost_snapshot numeric, unit_sale_price numeric
         )
         left join public.repair_parts saved
           on saved.id = requested.id and saved.ticket_id = p_ticket_id
         where saved.id is null
           or saved.source_type is distinct from requested.source_type
           or saved.product_id is distinct from requested.product_id
           or saved.supplier_id is distinct from requested.supplier_id
           or saved.settlement_type is distinct from
             coalesce(requested.settlement_type,'already_recorded')
           or saved.quantity is distinct from requested.quantity
           or saved.unit_cost_snapshot is distinct from
             requested.unit_cost_snapshot
           or saved.unit_sale_price is distinct from requested.unit_sale_price
       ) then return p_ticket_id;
    end if;
    raise exception 'Finalized repair parts cannot be edited.';
  elsif v_ticket.status = 'cancelled' then
    raise exception 'Cancelled repair parts cannot be edited.';
  end if;
  if jsonb_typeof(p_parts) <> 'array' then
    raise exception 'Repair parts must be an array.';
  end if;
  delete from public.repair_parts
  where ticket_id = p_ticket_id and state = 'planned';
  for v_part in select * from jsonb_to_recordset(p_parts) as x(
    id uuid, source_type text, product_id uuid, supplier_id uuid,
    settlement_type text,
    name text, quantity integer, unit_cost_snapshot numeric,
    unit_sale_price numeric
  )
  loop
    if v_part.source_type not in ('inventory','direct_purchase') or
       coalesce(v_part.quantity,0) <= 0 or
       coalesce(v_part.unit_cost_snapshot,-1) < 0 or
       coalesce(v_part.unit_sale_price,-1) < 0 then
      raise exception 'Invalid repair part.';
    end if;
    if coalesce(v_part.settlement_type,'already_recorded')
       not in ('already_recorded','supplier_payable') or
       (v_part.settlement_type = 'supplier_payable'
        and v_part.supplier_id is null) then
      raise exception 'Invalid direct-part settlement.';
    end if;
    if v_part.source_type = 'inventory' then
      select * into v_product from public.products
      where id = v_part.product_id and tenant_id = v_ticket.tenant_id
        and branch_id = v_ticket.branch_id and is_active;
      if not found then raise exception 'Repair inventory product not found.'; end if;
    elsif nullif(trim(v_part.name),'') is null then
      raise exception 'Direct repair part name is required.';
    end if;
    insert into public.repair_parts(
      id, tenant_id, branch_id, ticket_id, source_type, product_id,
      supplier_id, name, quantity, unit_cost_snapshot, unit_sale_price,
      settlement_type, created_by
    ) values (
      coalesce(v_part.id,gen_random_uuid()), v_ticket.tenant_id,
      v_ticket.branch_id, p_ticket_id, v_part.source_type, v_part.product_id,
      v_part.supplier_id,
      case when v_part.source_type = 'inventory'
        then v_product.name else trim(v_part.name) end,
      v_part.quantity, v_part.unit_cost_snapshot, v_part.unit_sale_price,
      coalesce(v_part.settlement_type,'already_recorded'),
      auth.uid()
    );
  end loop;
  return p_ticket_id;
end
$function$;

create or replace function public.complete_repair_ticket_v2(
  p_ticket_id uuid, p_event_id uuid, p_customer_charge numeric,
  p_service_charge numeric default 0, p_discount numeric default 0,
  p_commission numeric default 0, p_other_direct_cost numeric default 0
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_ticket public.repair_tickets%rowtype;
  v_part record;
  v_inventory_cost numeric(12,2) := 0;
  v_direct_cost numeric(12,2) := 0;
  v_profit numeric(12,2);
  v_paid numeric(12,2);
begin
  select * into v_ticket from public.repair_tickets
  where id = p_ticket_id for update;
  if not found then raise exception 'Repair ticket not found.'; end if;
  if public.current_user_tenant_id() <> v_ticket.tenant_id then
    raise exception 'Not allowed.';
  end if;
  if not public.current_user_has_branch_permission(
    v_ticket.tenant_id, v_ticket.branch_id, 'repair.ticket.update'
  ) then raise exception 'Not allowed.'; end if;
  if exists (
    select 1 from public.repair_financial_events
    where tenant_id = v_ticket.tenant_id and branch_id = v_ticket.branch_id
      and source_event_key = 'repair:completion:' || p_event_id::text
  ) then return p_event_id; end if;
  if v_ticket.status in ('completed','delivered','cancelled') then
    raise exception 'Ticket cannot be completed from its current status.';
  end if;
  if p_customer_charge is null or p_customer_charge < 0 or
     coalesce(p_service_charge,0) < 0 or coalesce(p_discount,0) < 0 or
     coalesce(p_commission,0) < 0 or coalesce(p_other_direct_cost,0) < 0 then
    raise exception 'Repair financial amounts cannot be negative.';
  end if;

  for v_part in select * from public.repair_parts
    where ticket_id = p_ticket_id and state = 'planned' for update
  loop
    if v_part.source_type = 'inventory' then
      update public.inventory set quantity = quantity - v_part.quantity,
        updated_at = now()
      where branch_id = v_ticket.branch_id
        and product_id = v_part.product_id
        and quantity >= v_part.quantity;
      if not found then
        raise exception 'Insufficient repair-part stock.';
      end if;
      v_inventory_cost := v_inventory_cost +
        v_part.quantity * v_part.unit_cost_snapshot;
    else
      v_direct_cost := v_direct_cost +
        v_part.quantity * v_part.unit_cost_snapshot;
      if v_part.settlement_type = 'supplier_payable' then
        insert into public.supplier_ledger_entries(
          tenant_id, branch_id, supplier_id, entry_type, direction, amount,
          source_event_key, reference_type, reference_id, description,
          occurred_at, created_by
        ) values (
          v_ticket.tenant_id, v_ticket.branch_id, v_part.supplier_id,
          'goods_receipt', 'increase',
          v_part.quantity * v_part.unit_cost_snapshot,
          'repair:direct-part:' || v_part.id::text,
          'repair_part', v_part.id, 'Direct repair part', now(), auth.uid()
        ) on conflict (tenant_id,branch_id,source_event_key) do nothing;
        update public.suppliers set outstanding_balance =
          outstanding_balance + v_part.quantity * v_part.unit_cost_snapshot
        where id = v_part.supplier_id;
      end if;
    end if;
    update public.repair_parts set state = 'consumed',
      consumed_at = now(), updated_at = now() where id = v_part.id;
  end loop;

  select coalesce(sum(amount),0) into v_paid
  from public.repair_payments where ticket_id = p_ticket_id;
  if v_paid > p_customer_charge + 0.01 then
    raise exception 'Customer charge cannot be below payments already received.';
  end if;
  v_profit := p_customer_charge - v_inventory_cost - v_direct_cost
    - coalesce(p_commission,0) - coalesce(p_other_direct_cost,0);
  insert into public.repair_financial_events(
    id, tenant_id, branch_id, ticket_id, event_type, source_event_key,
    revenue_amount, inventory_cost, direct_parts_cost, commission_cost,
    other_direct_cost, gross_profit, occurred_at, created_by
  ) values (
    p_event_id, v_ticket.tenant_id, v_ticket.branch_id, p_ticket_id,
    'completion', 'repair:completion:' || p_event_id::text,
    p_customer_charge, v_inventory_cost, v_direct_cost,
    coalesce(p_commission,0), coalesce(p_other_direct_cost,0),
    v_profit, now(), auth.uid()
  );
  update public.repair_tickets set status = 'completed',
    customer_charge = p_customer_charge, total_cost = p_customer_charge,
    service_charge = coalesce(p_service_charge,0),
    discount_amount = coalesce(p_discount,0),
    parts_cost = v_inventory_cost + v_direct_cost,
    labor_cost = coalesce(p_commission,0),
    per_job_commission = coalesce(p_commission,0),
    other_direct_cost = coalesce(p_other_direct_cost,0),
    completed_at = now(), finalized_at = now(), updated_at = now()
  where id = p_ticket_id;
  insert into public.repair_status_logs(
    ticket_id, tenant_id, branch_id, old_status, new_status,
    changed_by, note
  ) values (
    p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, v_ticket.status,
    'completed', auth.uid(), 'Repair financial completion'
  );
  return p_event_id;
end
$function$;

create or replace function public.cancel_repair_ticket_v2(
  p_ticket_id uuid, p_event_id uuid
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_ticket public.repair_tickets%rowtype;
  v_completion public.repair_financial_events%rowtype;
  v_part record;
  v_paid numeric(12,2);
begin
  select * into v_ticket from public.repair_tickets
  where id = p_ticket_id for update;
  if not found then raise exception 'Repair ticket not found.'; end if;
  if public.current_user_tenant_id() <> v_ticket.tenant_id then
    raise exception 'Not allowed.';
  end if;
  if not public.current_user_has_branch_permission(
    v_ticket.tenant_id, v_ticket.branch_id, 'repair.ticket.update'
  ) then raise exception 'Not allowed.'; end if;
  if v_ticket.status = 'cancelled' then return p_event_id; end if;
  select coalesce(sum(amount),0) into v_paid from public.repair_payments
  where ticket_id = p_ticket_id;
  if v_paid > 0 then
    raise exception 'Refund or retain customer credit before cancellation.';
  end if;
  if v_ticket.status in ('completed','delivered') then
    select * into v_completion from public.repair_financial_events
    where ticket_id = p_ticket_id and event_type = 'completion'
    order by occurred_at desc limit 1 for update;
    if not found then raise exception 'Completion snapshot is missing.'; end if;
    for v_part in select * from public.repair_parts
      where ticket_id = p_ticket_id and state = 'consumed' for update
    loop
      if v_part.source_type = 'inventory' then
        insert into public.inventory(branch_id, product_id, quantity, updated_at)
        values (v_ticket.branch_id, v_part.product_id, v_part.quantity, now())
        on conflict (branch_id, product_id) do update set
          quantity = public.inventory.quantity + excluded.quantity,
          updated_at = now();
      end if;
      if v_part.source_type = 'direct_purchase'
         and v_part.settlement_type = 'supplier_payable' then
        if not exists (
          select 1 from public.suppliers
          where id = v_part.supplier_id
            and outstanding_balance >=
              v_part.quantity * v_part.unit_cost_snapshot
        ) then
          raise exception
            'Resolve paid supplier amount before repair cancellation.';
        end if;
        insert into public.supplier_ledger_entries(
          tenant_id, branch_id, supplier_id, entry_type, direction, amount,
          source_event_key, reference_type, reference_id, description,
          occurred_at, created_by
        ) values (
          v_ticket.tenant_id, v_ticket.branch_id, v_part.supplier_id,
          'credit_note', 'decrease',
          v_part.quantity * v_part.unit_cost_snapshot,
          'repair:direct-part-reversal:' || v_part.id::text,
          'repair_part', v_part.id, 'Cancelled direct repair part',
          now(), auth.uid()
        ) on conflict (tenant_id,branch_id,source_event_key) do nothing;
        update public.suppliers set outstanding_balance =
          outstanding_balance -
            v_part.quantity * v_part.unit_cost_snapshot
        where id = v_part.supplier_id;
      end if;
      update public.repair_parts set state = 'reversed',
        reversed_at = now(), updated_at = now() where id = v_part.id;
    end loop;
    insert into public.repair_financial_events(
      id, tenant_id, branch_id, ticket_id, event_type, source_event_key,
      revenue_amount, inventory_cost, direct_parts_cost, commission_cost,
      other_direct_cost, gross_profit, reversal_of_event_id,
      occurred_at, created_by
    ) values (
      p_event_id, v_ticket.tenant_id, v_ticket.branch_id, p_ticket_id,
      'reversal', 'repair:reversal:' || p_event_id::text,
      -v_completion.revenue_amount, -v_completion.inventory_cost,
      -v_completion.direct_parts_cost, -v_completion.commission_cost,
      -v_completion.other_direct_cost, -v_completion.gross_profit,
      v_completion.id, now(), auth.uid()
    );
  end if;
  update public.repair_tickets set status = 'cancelled',
    reversed_at = case when finalized_at is null then null else now() end,
    updated_at = now() where id = p_ticket_id;
  insert into public.repair_status_logs(
    ticket_id, tenant_id, branch_id, old_status, new_status,
    changed_by, note
  ) values (
    p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, v_ticket.status,
    'cancelled', auth.uid(), 'Repair cancellation'
  );
  return p_event_id;
end
$function$;

create or replace function public.archive_repair_ticket_v2(p_ticket_id uuid)
returns boolean
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare v_ticket public.repair_tickets%rowtype;
begin
  select * into v_ticket from public.repair_tickets
  where id = p_ticket_id for update;
  if not found then raise exception 'Repair ticket not found.'; end if;
  if public.current_user_tenant_id() <> v_ticket.tenant_id or
     not public.current_user_has_branch_permission(
       v_ticket.tenant_id, v_ticket.branch_id, 'repair.ticket.update'
     ) then raise exception 'Not allowed.'; end if;
  update public.repair_tickets set archived_at = coalesce(archived_at,now()),
    archived_by = coalesce(archived_by,auth.uid()), updated_at = now()
  where id = p_ticket_id;
  return true;
end
$function$;

revoke all on function public.complete_repair_ticket_v2(
  uuid,uuid,numeric,numeric,numeric,numeric,numeric
) from public, anon;
revoke all on function public.save_repair_parts_v2(uuid,jsonb)
  from public, anon;
grant execute on function public.save_repair_parts_v2(uuid,jsonb)
  to authenticated, service_role;
grant execute on function public.complete_repair_ticket_v2(
  uuid,uuid,numeric,numeric,numeric,numeric,numeric
) to authenticated, service_role;
revoke all on function public.cancel_repair_ticket_v2(uuid,uuid)
  from public, anon;
grant execute on function public.cancel_repair_ticket_v2(uuid,uuid)
  to authenticated, service_role;
revoke all on function public.archive_repair_ticket_v2(uuid)
  from public, anon;
grant execute on function public.archive_repair_ticket_v2(uuid)
  to authenticated, service_role;
