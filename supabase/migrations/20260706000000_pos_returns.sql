alter table if exists public.tenant_settings
  add column if not exists return_approval_threshold numeric not null default 25000,
  add column if not exists return_window_days integer not null default 7,
  add column if not exists cashier_discount_fixed_limit numeric not null default 500,
  add column if not exists cashier_discount_percent_limit numeric not null default 10,
  add column if not exists manager_discount_fixed_limit numeric not null default 5000,
  add column if not exists manager_discount_percent_limit numeric not null default 25,
  add column if not exists discount_audit_threshold numeric not null default 1000,
  add column if not exists receipt_footer text;

alter table if exists public.users
  add column if not exists approval_pin text;

alter table if exists public.customers
  add column if not exists credit_limit numeric,
  add column if not exists outstanding_balance numeric not null default 0;

create unique index if not exists idx_customers_tenant_phone_unique
  on public.customers(tenant_id, phone)
  where phone is not null and phone <> '';

do $$
declare
  payment_method_constraint text;
begin
  select conname
  into payment_method_constraint
  from pg_constraint
  where conrelid = 'public.sale_payments'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%method%'
  limit 1;

  if payment_method_constraint is not null then
    execute format(
      'alter table public.sale_payments drop constraint %I',
      payment_method_constraint
    );
  end if;

  alter table public.sale_payments
    add constraint sale_payments_method_check
    check (method in ('cash', 'easypaisa', 'jazzcash', 'card', 'credit'));
end $$;

create table if not exists public.sale_returns (
  id uuid primary key,
  original_sale_id uuid not null references public.sales(id),
  branch_id uuid not null references public.branches(id),
  user_id uuid not null references auth.users(id),
  status text not null default 'approved'
    check (status in ('approved', 'pending_approval', 'rejected')),
  refund_method text not null default 'cash'
    check (refund_method in ('cash', 'credit')),
  refund_amount numeric not null default 0,
  approval_required_reason text,
  override_reason text,
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.sale_return_items (
  id bigserial primary key,
  return_id uuid not null references public.sale_returns(id) on delete cascade,
  original_sale_id uuid not null references public.sales(id),
  product_id uuid not null references public.products(id),
  product_name text not null,
  product_sku text,
  quantity integer not null check (quantity > 0),
  refund_amount numeric not null default 0
);

create index if not exists idx_sale_returns_original_sale
  on public.sale_returns(original_sale_id);

create index if not exists idx_sale_return_items_original_sale
  on public.sale_return_items(original_sale_id);

create index if not exists idx_sale_return_items_return
  on public.sale_return_items(return_id);

create table if not exists public.discount_audit_logs (
  id uuid primary key,
  sale_id uuid references public.sales(id),
  branch_id uuid not null references public.branches(id),
  cashier_id uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  scope text not null check (scope in ('cart', 'item')),
  product_id uuid references public.products(id),
  discount_type text not null check (discount_type in ('fixed', 'percent')),
  requested_value numeric not null,
  discount_amount numeric not null,
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.receipt_delivery_logs (
  id uuid primary key,
  sale_id uuid not null references public.sales(id),
  delivery_method text not null check (
    delivery_method in ('thermal_print', 'whatsapp', 'email')
  ),
  recipient text,
  duplicate boolean not null default false,
  status text not null default 'sent',
  created_at timestamptz not null default now()
);

create table if not exists public.customer_settlements (
  id uuid primary key,
  customer_id uuid not null references public.customers(id),
  branch_id uuid not null references public.branches(id),
  user_id uuid not null references auth.users(id),
  amount numeric not null check (amount > 0),
  method text not null check (
    method in ('cash', 'easypaisa', 'jazzcash', 'card')
  ),
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists idx_discount_audit_logs_sale
  on public.discount_audit_logs(sale_id);

create index if not exists idx_receipt_delivery_logs_sale
  on public.receipt_delivery_logs(sale_id);

create index if not exists idx_customer_settlements_customer
  on public.customer_settlements(customer_id);

alter table public.sale_returns enable row level security;
alter table public.sale_return_items enable row level security;
alter table public.discount_audit_logs enable row level security;
alter table public.receipt_delivery_logs enable row level security;
alter table public.customer_settlements enable row level security;

drop policy if exists "tenant users can update customers" on public.customers;
create policy "tenant users can update customers"
on public.customers
for update
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = customers.tenant_id
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = customers.tenant_id
  )
);

drop policy if exists "tenant users can read sale returns" on public.sale_returns;
create policy "tenant users can read sale returns"
on public.sale_returns
for select
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = sale_returns.branch_id
  )
);

drop policy if exists "tenant users can insert sale returns" on public.sale_returns;
create policy "tenant users can insert sale returns"
on public.sale_returns
for insert
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = sale_returns.branch_id
  )
);

drop policy if exists "tenant managers can update sale returns" on public.sale_returns;
create policy "tenant managers can update sale returns"
on public.sale_returns
for update
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = sale_returns.branch_id
      and u.role in ('manager', 'owner')
  )
);

drop policy if exists "tenant users can read sale return items" on public.sale_return_items;
create policy "tenant users can read sale return items"
on public.sale_return_items
for select
using (
  exists (
    select 1
    from public.sale_returns r
    join public.users u on u.id = auth.uid()
    join public.branches b on b.id = r.branch_id and b.tenant_id = u.tenant_id
    where r.id = sale_return_items.return_id
  )
);

drop policy if exists "tenant users can insert sale return items" on public.sale_return_items;
create policy "tenant users can insert sale return items"
on public.sale_return_items
for insert
with check (
  exists (
    select 1
    from public.sale_returns r
    join public.users u on u.id = auth.uid()
    join public.branches b on b.id = r.branch_id and b.tenant_id = u.tenant_id
    where r.id = sale_return_items.return_id
  )
);

drop policy if exists "tenant users can delete sale return items" on public.sale_return_items;
create policy "tenant users can delete sale return items"
on public.sale_return_items
for delete
using (
  exists (
    select 1
    from public.sale_returns r
    join public.users u on u.id = auth.uid()
    join public.branches b on b.id = r.branch_id and b.tenant_id = u.tenant_id
    where r.id = sale_return_items.return_id
  )
);

drop policy if exists "tenant users can insert discount audits" on public.discount_audit_logs;
create policy "tenant users can insert discount audits"
on public.discount_audit_logs
for insert
with check (
  cashier_id = auth.uid()
  and exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = discount_audit_logs.branch_id
  )
);

drop policy if exists "tenant users can read discount audits" on public.discount_audit_logs;
create policy "tenant users can read discount audits"
on public.discount_audit_logs
for select
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = discount_audit_logs.branch_id
  )
);

drop policy if exists "tenant users can insert receipt logs" on public.receipt_delivery_logs;
create policy "tenant users can insert receipt logs"
on public.receipt_delivery_logs
for insert
with check (
  exists (
    select 1
    from public.sales s
    join public.branches b on b.id = s.branch_id
    join public.users u on u.tenant_id = b.tenant_id
    where s.id = receipt_delivery_logs.sale_id
      and u.id = auth.uid()
  )
);

drop policy if exists "tenant users can read customer settlements" on public.customer_settlements;
create policy "tenant users can read customer settlements"
on public.customer_settlements
for select
using (
  exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = customer_settlements.branch_id
  )
);

drop policy if exists "tenant users can insert customer settlements" on public.customer_settlements;
create policy "tenant users can insert customer settlements"
on public.customer_settlements
for insert
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.users u
    join public.branches b on b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and b.id = customer_settlements.branch_id
  )
);
