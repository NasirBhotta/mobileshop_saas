-- Migration for Customer Buy-In (Second-Hand Device Purchases)
create table if not exists public.customer_purchases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  seller_name text not null,
  seller_cnic text not null,
  seller_phone text not null,
  seller_address text,
  seller_photo_url text,
  cnic_front_url text,
  cnic_back_url text,
  product_id uuid not null references public.products(id) on delete cascade,
  product_name text not null,
  category_id uuid references public.categories(id) on delete set null,
  imei1 text not null,
  imei2 text,
  color text,
  storage text,
  device_condition text,
  accessories text,
  purchase_price numeric not null default 0,
  expected_sale_price numeric not null default 0,
  payment_account_id uuid references public.accounts(id) on delete set null,
  payment_method text,
  notes text,
  declaration_agreed boolean not null default true,
  status text not null default 'in_stock',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Indexes for performance
create index if not exists idx_customer_purchases_tenant on public.customer_purchases(tenant_id);
create index if not exists idx_customer_purchases_branch on public.customer_purchases(branch_id);
create index if not exists idx_customer_purchases_imei on public.customer_purchases(imei1);
create index if not exists idx_customer_purchases_cnic on public.customer_purchases(seller_cnic);
create index if not exists idx_customer_purchases_created_at on public.customer_purchases(created_at desc);

-- Enable RLS
alter table public.customer_purchases enable row level security;

-- Tenant isolation policies
create policy "Tenant users can view customer purchases"
  on public.customer_purchases for select
  using (tenant_id in (select tenant_id from public.users where id = auth.uid()));

create policy "Tenant users can insert customer purchases"
  on public.customer_purchases for insert
  with check (tenant_id in (select tenant_id from public.users where id = auth.uid()));

create policy "Tenant users can update customer purchases"
  on public.customer_purchases for update
  using (tenant_id in (select tenant_id from public.users where id = auth.uid()));
