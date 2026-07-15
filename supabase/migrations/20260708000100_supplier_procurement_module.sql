create extension if not exists pgcrypto;

-- ═══════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════

create or replace function public.current_user_tenant_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select tenant_id
  from public.users
  where id = auth.uid()
  limit 1
$$;

create table if not exists public.tenant_addons (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  addon_key text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  unique(tenant_id, addon_key)
);

create or replace function public.tenant_procurement_enabled(p_tenant_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tenants t
    where t.id = p_tenant_id
      and (
        lower(t.plan) in ('business', 'enterprise')
        or exists (
          select 1
          from public.tenant_addons a
          where a.tenant_id = t.id
            and a.addon_key = 'supplier_procurement'
            and a.enabled = true
        )
      )
  )
$$;

create or replace function public.ensure_procurement_enabled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tenant_procurement_enabled(new.tenant_id) then
    raise exception 'Supplier & Procurement module is available only on Business/Enterprise plan or enabled add-on.';
  end if;

  return new;
end;
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ═══════════════════════════════════════
-- Suppliers
-- ═══════════════════════════════════════

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,

  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  city text,

  payment_terms text,
  outstanding_balance numeric(12,2) not null default 0,

  notes text,
  is_active boolean not null default true,

  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(tenant_id, name)
);

create index if not exists idx_suppliers_tenant on public.suppliers(tenant_id);
create index if not exists idx_suppliers_branch on public.suppliers(branch_id);
create index if not exists idx_suppliers_active on public.suppliers(is_active);

drop trigger if exists trg_suppliers_updated_at on public.suppliers;
create trigger trg_suppliers_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

drop trigger if exists trg_suppliers_procurement_enabled on public.suppliers;
create trigger trg_suppliers_procurement_enabled
before insert or update on public.suppliers
for each row execute function public.ensure_procurement_enabled();

-- Catalog product linkage
create table if not exists public.supplier_products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  supplier_sku text,
  last_cost numeric(12,2),
  created_at timestamptz not null default now(),
  unique(supplier_id, product_id)
);

create index if not exists idx_supplier_products_supplier on public.supplier_products(supplier_id);
create index if not exists idx_supplier_products_product on public.supplier_products(product_id);

drop trigger if exists trg_supplier_products_procurement_enabled on public.supplier_products;
create trigger trg_supplier_products_procurement_enabled
before insert or update on public.supplier_products
for each row execute function public.ensure_procurement_enabled();

-- ═══════════════════════════════════════
-- Purchase Orders
-- ═══════════════════════════════════════

create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,

  po_no text not null,
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'partially_received', 'received', 'cancelled')),

  expected_delivery_at timestamptz,
  notes text,

  total_expected_cost numeric(12,2) not null default 0,
  total_received_cost numeric(12,2) not null default 0,

  created_by uuid references public.users(id) on delete set null,
  sent_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(branch_id, po_no)
);

create index if not exists idx_purchase_orders_tenant on public.purchase_orders(tenant_id);
create index if not exists idx_purchase_orders_branch on public.purchase_orders(branch_id);
create index if not exists idx_purchase_orders_supplier on public.purchase_orders(supplier_id);
create index if not exists idx_purchase_orders_status on public.purchase_orders(status);

drop trigger if exists trg_purchase_orders_updated_at on public.purchase_orders;
create trigger trg_purchase_orders_updated_at
before update on public.purchase_orders
for each row execute function public.set_updated_at();

drop trigger if exists trg_purchase_orders_procurement_enabled on public.purchase_orders;
create trigger trg_purchase_orders_procurement_enabled
before insert or update on public.purchase_orders
for each row execute function public.ensure_procurement_enabled();

create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,

  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  product_sku text,

  ordered_quantity integer not null check (ordered_quantity > 0),
  received_quantity integer not null default 0 check (received_quantity >= 0),

  negotiated_unit_cost numeric(12,2) not null check (negotiated_unit_cost >= 0),
  actual_unit_cost numeric(12,2),

  line_total numeric(12,2) not null default 0,

  created_at timestamptz not null default now(),

  check (received_quantity <= ordered_quantity)
);

create index if not exists idx_po_items_po on public.purchase_order_items(purchase_order_id);
create index if not exists idx_po_items_product on public.purchase_order_items(product_id);

drop trigger if exists trg_po_items_procurement_enabled on public.purchase_order_items;
create trigger trg_po_items_procurement_enabled
before insert or update on public.purchase_order_items
for each row execute function public.ensure_procurement_enabled();

-- ═══════════════════════════════════════
-- Goods Receiving
-- ═══════════════════════════════════════

create table if not exists public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,

  receipt_no text not null,
  note text,
  total_received_value numeric(12,2) not null default 0,

  received_by uuid references public.users(id) on delete set null,
  received_at timestamptz not null default now(),

  unique(branch_id, receipt_no)
);

create index if not exists idx_goods_receipts_po on public.goods_receipts(purchase_order_id);
create index if not exists idx_goods_receipts_supplier on public.goods_receipts(supplier_id);

drop trigger if exists trg_goods_receipts_procurement_enabled on public.goods_receipts;
create trigger trg_goods_receipts_procurement_enabled
before insert or update on public.goods_receipts
for each row execute function public.ensure_procurement_enabled();

create table if not exists public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  goods_receipt_id uuid not null references public.goods_receipts(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete restrict,

  product_id uuid not null references public.products(id) on delete restrict,
  received_quantity integer not null check (received_quantity > 0),
  actual_unit_cost numeric(12,2) not null check (actual_unit_cost >= 0),
  update_product_cost boolean not null default false,

  line_total numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_gr_items_receipt on public.goods_receipt_items(goods_receipt_id);
create index if not exists idx_gr_items_po on public.goods_receipt_items(purchase_order_id);

drop trigger if exists trg_gr_items_procurement_enabled on public.goods_receipt_items;
create trigger trg_gr_items_procurement_enabled
before insert or update on public.goods_receipt_items
for each row execute function public.ensure_procurement_enabled();

-- ═══════════════════════════════════════
-- Supplier Payments
-- ═══════════════════════════════════════

create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,

  amount numeric(12,2) not null check (amount > 0),
  method text,
  note text,

  paid_by uuid references public.users(id) on delete set null,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists idx_supplier_payments_supplier on public.supplier_payments(supplier_id);
create index if not exists idx_supplier_payments_branch on public.supplier_payments(branch_id);

drop trigger if exists trg_supplier_payments_procurement_enabled on public.supplier_payments;
create trigger trg_supplier_payments_procurement_enabled
before insert or update on public.supplier_payments
for each row execute function public.ensure_procurement_enabled();

-- ═══════════════════════════════════════
-- RPC: Create PO
-- ═══════════════════════════════════════

create or replace function public.create_purchase_order(
  p_po_id uuid,
  p_po_no text,
  p_tenant_id uuid,
  p_branch_id uuid,
  p_supplier_id uuid,
  p_expected_delivery_at timestamptz,
  p_notes text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_product record;
  v_total numeric(12,2) := 0;
begin
  if not public.tenant_procurement_enabled(p_tenant_id) then
    raise exception 'Supplier & Procurement module is not enabled.';
  end if;

  if public.current_user_tenant_id() <> p_tenant_id then
    raise exception 'Not allowed.';
  end if;

  if exists (select 1 from public.purchase_orders where id = p_po_id) then
    return p_po_id;
  end if;

  if jsonb_array_length(p_items) = 0 then
    raise exception 'Purchase order must have at least one item.';
  end if;

  insert into public.purchase_orders(
    id, tenant_id, branch_id, supplier_id, po_no, status,
    expected_delivery_at, notes, total_expected_cost, created_by
  )
  values (
    p_po_id, p_tenant_id, p_branch_id, p_supplier_id, p_po_no, 'draft',
    p_expected_delivery_at, p_notes, 0, auth.uid()
  );

  for v_item in
    select *
    from jsonb_to_recordset(p_items) as x(
      id uuid,
      product_id uuid,
      product_name text,
      product_sku text,
      ordered_quantity integer,
      negotiated_unit_cost numeric
    )
  loop
    if v_item.ordered_quantity <= 0 then
      raise exception 'Ordered quantity must be greater than zero.';
    end if;

    if v_item.negotiated_unit_cost < 0 then
      raise exception 'Unit cost cannot be negative.';
    end if;

    select id, name, sku
    into v_product
    from public.products
    where id = v_item.product_id
      and tenant_id = p_tenant_id
      and branch_id = p_branch_id
      and is_active = true
    limit 1;

    if not found then
      raise exception 'Product does not exist in catalog.';
    end if;

    insert into public.purchase_order_items(
      id, tenant_id, purchase_order_id, product_id,
      product_name, product_sku, ordered_quantity,
      negotiated_unit_cost, line_total
    )
    values (
      coalesce(v_item.id, gen_random_uuid()),
      p_tenant_id,
      p_po_id,
      v_item.product_id,
      coalesce(nullif(v_item.product_name, ''), v_product.name),
      coalesce(v_item.product_sku, v_product.sku),
      v_item.ordered_quantity,
      v_item.negotiated_unit_cost,
      v_item.ordered_quantity * v_item.negotiated_unit_cost
    );

    insert into public.supplier_products(
      tenant_id, supplier_id, product_id, last_cost
    )
    values (
      p_tenant_id, p_supplier_id, v_item.product_id, v_item.negotiated_unit_cost
    )
    on conflict (supplier_id, product_id)
    do update set last_cost = excluded.last_cost;

    v_total := v_total + (v_item.ordered_quantity * v_item.negotiated_unit_cost);
  end loop;

  update public.purchase_orders
  set total_expected_cost = v_total
  where id = p_po_id;

  return p_po_id;
end;
$$;

-- ═══════════════════════════════════════
-- RPC: Receive goods
-- ═══════════════════════════════════════

create or replace function public.receive_purchase_order_goods(
  p_receipt_id uuid,
  p_receipt_no text,
  p_po_id uuid,
  p_note text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po record;
  v_item record;
  v_po_item record;
  v_line_total numeric(12,2);
  v_total numeric(12,2) := 0;
  v_has_any_received boolean := false;
  v_all_received boolean := false;
begin
  select *
  into v_po
  from public.purchase_orders
  where id = p_po_id
  for update;

  if not found then
    raise exception 'Purchase order not found.';
  end if;

  if public.current_user_tenant_id() <> v_po.tenant_id then
    raise exception 'Not allowed.';
  end if;

  if v_po.status = 'cancelled' then
    raise exception 'Cannot receive goods against cancelled PO.';
  end if;

  if exists (select 1 from public.goods_receipts where id = p_receipt_id) then
    return p_receipt_id;
  end if;

  if v_po.status = 'received' then
    raise exception 'PO is already fully received.';
  end if;

  if jsonb_array_length(p_items) = 0 then
    raise exception 'No received items provided.';
  end if;

  insert into public.goods_receipts(
    id, tenant_id, branch_id, purchase_order_id, supplier_id,
    receipt_no, note, received_by, total_received_value
  )
  values (
    p_receipt_id,
    v_po.tenant_id,
    v_po.branch_id,
    v_po.id,
    v_po.supplier_id,
    p_receipt_no,
    p_note,
    auth.uid(),
    0
  );

  for v_item in
    select *
    from jsonb_to_recordset(p_items) as x(
      purchase_order_item_id uuid,
      received_quantity integer,
      actual_unit_cost numeric,
      update_product_cost boolean
    )
  loop
    if v_item.received_quantity <= 0 then
      continue;
    end if;

    select *
    into v_po_item
    from public.purchase_order_items
    where id = v_item.purchase_order_item_id
      and purchase_order_id = v_po.id
    for update;

    if not found then
      raise exception 'PO item not found.';
    end if;

    if v_po_item.received_quantity + v_item.received_quantity > v_po_item.ordered_quantity then
      raise exception 'Received quantity cannot exceed ordered quantity.';
    end if;

    v_line_total := v_item.received_quantity * v_item.actual_unit_cost;
    v_total := v_total + v_line_total;

    insert into public.goods_receipt_items(
      tenant_id, goods_receipt_id, purchase_order_id, purchase_order_item_id,
      product_id, received_quantity, actual_unit_cost, update_product_cost, line_total
    )
    values (
      v_po.tenant_id,
      p_receipt_id,
      v_po.id,
      v_po_item.id,
      v_po_item.product_id,
      v_item.received_quantity,
      v_item.actual_unit_cost,
      coalesce(v_item.update_product_cost, false),
      v_line_total
    );

    update public.purchase_order_items
    set received_quantity = received_quantity + v_item.received_quantity,
        actual_unit_cost = v_item.actual_unit_cost
    where id = v_po_item.id;

    insert into public.inventory(branch_id, product_id, quantity, updated_at)
    values (v_po.branch_id, v_po_item.product_id, v_item.received_quantity, now())
    on conflict (branch_id, product_id)
    do update set
      quantity = public.inventory.quantity + excluded.quantity,
      updated_at = now();

    if coalesce(v_item.update_product_cost, false) then
      update public.products
      set cost_price = v_item.actual_unit_cost
      where id = v_po_item.product_id
        and tenant_id = v_po.tenant_id
        and branch_id = v_po.branch_id;
    end if;
  end loop;

  if v_total <= 0 then
    raise exception 'Received quantity must be greater than zero.';
  end if;

  update public.goods_receipts
  set total_received_value = v_total
  where id = p_receipt_id;

  update public.purchase_orders
  set total_received_cost = total_received_cost + v_total
  where id = v_po.id;

  select exists (
    select 1
    from public.purchase_order_items
    where purchase_order_id = v_po.id
      and received_quantity > 0
  )
  into v_has_any_received;

  select not exists (
    select 1
    from public.purchase_order_items
    where purchase_order_id = v_po.id
      and received_quantity < ordered_quantity
  )
  into v_all_received;

  update public.purchase_orders
  set status = case
      when v_all_received then 'received'
      when v_has_any_received then 'partially_received'
      else status
    end
  where id = v_po.id;

  update public.suppliers
  set outstanding_balance = outstanding_balance + v_total
  where id = v_po.supplier_id;

  return p_receipt_id;
end;
$$;

-- ═══════════════════════════════════════
-- RPC: Supplier payment
-- ═══════════════════════════════════════

create or replace function public.record_supplier_payment(
  p_payment_id uuid,
  p_tenant_id uuid,
  p_branch_id uuid,
  p_supplier_id uuid,
  p_amount numeric,
  p_method text,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_user_tenant_id() <> p_tenant_id then
    raise exception 'Not allowed.';
  end if;

  if p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  if exists (select 1 from public.supplier_payments where id = p_payment_id) then
    return p_payment_id;
  end if;

  insert into public.supplier_payments(
    id, tenant_id, branch_id, supplier_id, amount, method, note, paid_by
  )
  values (
    p_payment_id, p_tenant_id, p_branch_id, p_supplier_id,
    p_amount, p_method, p_note, auth.uid()
  );

  update public.suppliers
  set outstanding_balance = greatest(outstanding_balance - p_amount, 0)
  where id = p_supplier_id
    and tenant_id = p_tenant_id;

  return p_payment_id;
end;
$$;

-- ═══════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════

alter table public.tenant_addons enable row level security;
alter table public.suppliers enable row level security;
alter table public.supplier_products enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;
alter table public.supplier_payments enable row level security;

drop policy if exists "tenant users manage tenant addons" on public.tenant_addons;
create policy "tenant users manage tenant addons"
on public.tenant_addons for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users manage suppliers" on public.suppliers;
create policy "tenant users manage suppliers"
on public.suppliers for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users manage supplier products" on public.supplier_products;
create policy "tenant users manage supplier products"
on public.supplier_products for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users manage purchase orders" on public.purchase_orders;
create policy "tenant users manage purchase orders"
on public.purchase_orders for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users manage purchase order items" on public.purchase_order_items;
create policy "tenant users manage purchase order items"
on public.purchase_order_items for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users manage goods receipts" on public.goods_receipts;
create policy "tenant users manage goods receipts"
on public.goods_receipts for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users manage goods receipt items" on public.goods_receipt_items;
create policy "tenant users manage goods receipt items"
on public.goods_receipt_items for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users manage supplier payments" on public.supplier_payments;
create policy "tenant users manage supplier payments"
on public.supplier_payments for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());
