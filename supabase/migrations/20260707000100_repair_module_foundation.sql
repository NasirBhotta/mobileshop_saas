create extension if not exists pgcrypto;

-- ═══════════════════════════════════════
-- INVENTORY UNITS / IMEI UNITS
-- ═══════════════════════════════════════
create table if not exists public.inventory_units (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,

  imei text not null,

  status text not null default 'available'
    check (
      status in (
        'available',
        'sold',
        'in_repair',
        'returned',
        'lost',
        'damaged'
      )
    ),

  sale_id uuid null references public.sales(id) on delete set null,
  customer_id uuid null references public.customers(id) on delete set null,

  warranty_start_at timestamptz null,
  warranty_end_at timestamptz null,

  current_repair_ticket_id uuid null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint inventory_units_branch_imei_key unique (branch_id, imei)
);

create index if not exists idx_inventory_units_branch
  on public.inventory_units(branch_id);

create index if not exists idx_inventory_units_product
  on public.inventory_units(product_id);

create index if not exists idx_inventory_units_status
  on public.inventory_units(status);

create index if not exists idx_inventory_units_imei
  on public.inventory_units(imei);

create index if not exists idx_inventory_units_sale
  on public.inventory_units(sale_id);


-- ═══════════════════════════════════════
-- REPAIR TICKETS
-- ═══════════════════════════════════════
create table if not exists public.repair_tickets (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,

  ticket_no text not null,

  customer_id uuid null references public.customers(id) on delete set null,
  customer_name text not null,
  customer_phone text null,

  product_id uuid null references public.products(id) on delete set null,
  inventory_unit_id uuid null references public.inventory_units(id) on delete set null,

  device_brand text not null,
  device_model text not null,
  device_color text null,
  imei text null,

  fault_description text not null,

  technician_id uuid null references public.users(id) on delete set null,

  status text not null default 'received'
    check (
      status in (
        'received',
        'diagnosed',
        'in_progress',
        'waiting_part',
        'completed',
        'delivered',
        'cancelled'
      )
    ),

  estimated_cost numeric(12, 2) null check (estimated_cost is null or estimated_cost >= 0),
  estimated_completion_at timestamptz null,
  estimate_note text null,

  parts_cost numeric(12, 2) null check (parts_cost is null or parts_cost >= 0),
  labor_cost numeric(12, 2) null check (labor_cost is null or labor_cost >= 0),
  total_cost numeric(12, 2) null check (total_cost is null or total_cost >= 0),

  warranty_reference text null,
  warranty_note text null,
  is_warranty_repair boolean not null default false,

  created_by uuid not null references public.users(id),
  completed_at timestamptz null,
  delivered_at timestamptz null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint repair_tickets_branch_ticket_no_key unique (branch_id, ticket_no)
);

create index if not exists idx_repair_tickets_branch
  on public.repair_tickets(branch_id);

create index if not exists idx_repair_tickets_tenant
  on public.repair_tickets(tenant_id);

create index if not exists idx_repair_tickets_customer
  on public.repair_tickets(customer_id);

create index if not exists idx_repair_tickets_status
  on public.repair_tickets(status);

create index if not exists idx_repair_tickets_technician
  on public.repair_tickets(technician_id);

create index if not exists idx_repair_tickets_imei
  on public.repair_tickets(imei);

create index if not exists idx_repair_tickets_created_at
  on public.repair_tickets(created_at desc);


-- inventory_units -> repair_tickets FK, separate because tables reference each other
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'inventory_units_current_repair_ticket_id_fkey'
  ) then
    alter table public.inventory_units
      add constraint inventory_units_current_repair_ticket_id_fkey
      foreign key (current_repair_ticket_id)
      references public.repair_tickets(id)
      on delete set null;
  end if;
end $$;


-- ═══════════════════════════════════════
-- REPAIR STATUS LOGS
-- ═══════════════════════════════════════
create table if not exists public.repair_status_logs (
  id uuid primary key default gen_random_uuid(),

  ticket_id uuid not null references public.repair_tickets(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,

  old_status text null,
  new_status text not null,

  changed_by uuid not null references public.users(id),
  note text null,

  created_at timestamptz not null default now()
);

create index if not exists idx_repair_status_logs_ticket
  on public.repair_status_logs(ticket_id, created_at desc);

create index if not exists idx_repair_status_logs_branch
  on public.repair_status_logs(branch_id);

create index if not exists idx_repair_status_logs_changed_by
  on public.repair_status_logs(changed_by);


-- ═══════════════════════════════════════
-- UPDATED_AT HELPER
-- ═══════════════════════════════════════
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists inventory_units_set_updated_at on public.inventory_units;
create trigger inventory_units_set_updated_at
  before update on public.inventory_units
  for each row
  execute function public.set_updated_at();

drop trigger if exists repair_tickets_set_updated_at on public.repair_tickets;
create trigger repair_tickets_set_updated_at
  before update on public.repair_tickets
  for each row
  execute function public.set_updated_at();


-- ═══════════════════════════════════════
-- REPAIR TICKET CREATE TRIGGER
-- Ticket number generate + IMEI status update
-- ═══════════════════════════════════════
create or replace function public.before_repair_ticket_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unit_id uuid;
begin
  -- Ticket number app se na aaye to DB fallback generate kare
  if new.ticket_no is null or btrim(new.ticket_no) = '' then
    new.ticket_no :=
      'REP-' ||
      to_char(now(), 'YYYYMMDD') ||
      '-' ||
      upper(substr(new.id::text, 1, 6));
  end if;

  -- Agar inventory_unit_id already selected hai, usko in_repair karo
  if new.inventory_unit_id is not null then
    update public.inventory_units
    set
      status = 'in_repair',
      current_repair_ticket_id = new.id,
      updated_at = now()
    where id = new.inventory_unit_id
      and tenant_id = new.tenant_id
      and branch_id = new.branch_id;

    return new;
  end if;

  -- Agar IMEI + product_id mila hai, unit find/create karo aur in_repair karo
  if new.imei is not null
     and btrim(new.imei) <> ''
     and new.product_id is not null then

    insert into public.inventory_units (
      tenant_id,
      branch_id,
      product_id,
      imei,
      status,
      customer_id,
      current_repair_ticket_id
    )
    values (
      new.tenant_id,
      new.branch_id,
      new.product_id,
      btrim(new.imei),
      'in_repair',
      new.customer_id,
      new.id
    )
    on conflict (branch_id, imei)
    do update set
      status = 'in_repair',
      current_repair_ticket_id = excluded.current_repair_ticket_id,
      customer_id = coalesce(excluded.customer_id, public.inventory_units.customer_id),
      updated_at = now()
    returning id into v_unit_id;

    new.inventory_unit_id = v_unit_id;
  end if;

  return new;
end;
$$;

drop trigger if exists repair_ticket_before_insert on public.repair_tickets;
create trigger repair_ticket_before_insert
  before insert on public.repair_tickets
  for each row
  execute function public.before_repair_ticket_insert();


-- Initial status log when ticket is created
create or replace function public.after_repair_ticket_insert_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.repair_status_logs (
    ticket_id,
    tenant_id,
    branch_id,
    old_status,
    new_status,
    changed_by,
    note
  )
  values (
    new.id,
    new.tenant_id,
    new.branch_id,
    null,
    new.status,
    new.created_by,
    'Repair ticket created'
  );

  return new;
end;
$$;

drop trigger if exists repair_ticket_after_insert_log on public.repair_tickets;
create trigger repair_ticket_after_insert_log
  after insert on public.repair_tickets
  for each row
  execute function public.after_repair_ticket_insert_log();


-- ═══════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════
alter table public.inventory_units enable row level security;
alter table public.repair_tickets enable row level security;
alter table public.repair_status_logs enable row level security;


-- INVENTORY UNITS POLICY
drop policy if exists "tenant users can manage inventory units" on public.inventory_units;
create policy "tenant users can manage inventory units"
on public.inventory_units
for all
to authenticated
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = inventory_units.branch_id
      and u.tenant_id = inventory_units.tenant_id
  )
)
with check (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = inventory_units.branch_id
      and u.tenant_id = inventory_units.tenant_id
  )
);


-- REPAIR TICKETS POLICIES
drop policy if exists "tenant users can read repair tickets" on public.repair_tickets;
create policy "tenant users can read repair tickets"
on public.repair_tickets
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = repair_tickets.branch_id
      and u.tenant_id = repair_tickets.tenant_id
  )
);

drop policy if exists "tenant users can insert repair tickets" on public.repair_tickets;
create policy "tenant users can insert repair tickets"
on public.repair_tickets
for insert
to authenticated
with check (
  created_by = auth.uid()
  and exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = repair_tickets.branch_id
      and u.tenant_id = repair_tickets.tenant_id
  )
);

drop policy if exists "tenant users can update repair tickets" on public.repair_tickets;
create policy "tenant users can update repair tickets"
on public.repair_tickets
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = repair_tickets.branch_id
      and u.tenant_id = repair_tickets.tenant_id
  )
)
with check (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = repair_tickets.branch_id
      and u.tenant_id = repair_tickets.tenant_id
  )
);


-- REPAIR STATUS LOGS POLICIES
drop policy if exists "tenant users can read repair status logs" on public.repair_status_logs;
create policy "tenant users can read repair status logs"
on public.repair_status_logs
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = repair_status_logs.branch_id
      and u.tenant_id = repair_status_logs.tenant_id
  )
);

drop policy if exists "tenant users can insert repair status logs" on public.repair_status_logs;
create policy "tenant users can insert repair status logs"
on public.repair_status_logs
for insert
to authenticated
with check (
  changed_by = auth.uid()
  and exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = repair_status_logs.branch_id
      and u.tenant_id = repair_status_logs.tenant_id
  )
);