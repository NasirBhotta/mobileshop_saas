-- STAGING ONLY: synthetic customer rows to test tenant-bound RLS.
-- Run only in project diqwalqgfkusqefomtdl after checking that project is selected.
-- Creates/refreshes one synthetic Tenant B plus one customer in each tenant.
-- No Auth users, production records, schema, policies, or grants are changed.

begin;

do $guard$
begin
  if not exists (
    select 1 from public.tenants
    where id = '11111111-1111-4111-8111-111111111111'
      and shop_name = 'SEC-17 Staging Shop'
  ) then
    raise exception 'Staging fixture guard failed: SEC-17 Tenant A not found.';
  end if;
  if not exists (
    select 1 from public.branches
    where id = '22222222-2222-4222-8222-222222222222'
      and tenant_id = '11111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'Staging fixture guard failed: SEC-17 Tenant A branch not found.';
  end if;
  if not exists (
    select 1 from public.plans
    where key = 'starter' and is_active and deleted_at is null
  ) then
    raise exception 'Staging fixture guard failed: active starter plan missing.';
  end if;
end;
$guard$;

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values (
  '44444444-4444-4444-8444-444444444444',
  'SEC-17 Tenant B IDOR Target', 'mobile_retail', 1, 'starter', 'active', true
)
on conflict (id) do update
set shop_name = excluded.shop_name,
    business_type = excluded.business_type,
    branch_count = excluded.branch_count,
    plan = excluded.plan,
    status = excluded.status,
    setup_complete = excluded.setup_complete;

insert into public.branches (id, tenant_id, name, address, city, is_active)
values (
  '55555555-5555-4555-8555-555555555555',
  '44444444-4444-4444-8444-444444444444',
  'SEC-17 Tenant B Branch', 'Synthetic only', 'Staging', true
)
on conflict (id) do update
set tenant_id = excluded.tenant_id,
    name = excluded.name,
    is_active = true;

insert into public.customers (
  id, tenant_id, branch_id, full_name, phone, email, notes,
  credit_limit, outstanding_balance
)
values
  (
    '77777777-7777-4777-8777-777777777777',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'SEC-17 Tenant A RLS Control', 'SEC17-A-0001', null,
    'Synthetic RLS positive control', null, 0
  ),
  (
    '66666666-6666-4666-8666-666666666666',
    '44444444-4444-4444-8444-444444444444',
    '55555555-5555-4555-8555-555555555555',
    'SEC-17 Tenant B Hidden Target', 'SEC17-B-0001', null,
    'Synthetic cross-tenant RLS target', null, 0
  )
on conflict (id) do update
set tenant_id = excluded.tenant_id,
    branch_id = excluded.branch_id,
    full_name = excluded.full_name,
    phone = excluded.phone,
    email = excluded.email,
    notes = excluded.notes,
    credit_limit = excluded.credit_limit,
    outstanding_balance = excluded.outstanding_balance;

-- Products are a separate tenant-scoped surface from customer records.
-- These two rows are synthetic; fixed IDs make this fixture idempotent.
insert into public.products (
  id, tenant_id, branch_id, category_id, name, sku, description,
  sale_price, cost_price, imei_tracked, is_active, reorder_threshold, updated_at
)
values
  (
    '88888888-8888-4888-8888-888888888888',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    null, 'SEC-17 Tenant A Product Control', 'SEC17-A-PROD-0001',
    'Synthetic product RLS positive control', 1000, 500, false, true, 0, now()
  ),
  (
    '99999999-9999-4999-8999-999999999999',
    '44444444-4444-4444-8444-444444444444',
    '55555555-5555-4555-8555-555555555555',
    null, 'SEC-17 Tenant B Hidden Product', 'SEC17-B-PROD-0001',
    'Synthetic cross-tenant product target', 1000, 500, false, true, 0, now()
  )
on conflict (id) do update
set tenant_id = excluded.tenant_id,
    branch_id = excluded.branch_id,
    name = excluded.name,
    sku = excluded.sku,
    description = excluded.description,
    sale_price = excluded.sale_price,
    cost_price = excluded.cost_price,
    imei_tracked = excluded.imei_tracked,
    is_active = excluded.is_active,
    reorder_threshold = excluded.reorder_threshold,
    updated_at = excluded.updated_at;

select jsonb_build_object(
  'tenant_b_exists', exists (
    select 1 from public.tenants
    where id = '44444444-4444-4444-8444-444444444444'
      and shop_name = 'SEC-17 Tenant B IDOR Target'
  ),
  'tenant_a_control_exists', exists (
    select 1 from public.customers
    where id = '77777777-7777-4777-8777-777777777777'
      and tenant_id = '11111111-1111-4111-8111-111111111111'
  ),
  'tenant_b_target_exists', exists (
    select 1 from public.customers
    where id = '66666666-6666-4666-8666-666666666666'
      and tenant_id = '44444444-4444-4444-8444-444444444444'
  ),
  'tenant_a_product_control_exists', exists (
    select 1 from public.products
    where id = '88888888-8888-4888-8888-888888888888'
      and tenant_id = '11111111-1111-4111-8111-111111111111'
  ),
  'tenant_b_product_target_exists', exists (
    select 1 from public.products
    where id = '99999999-9999-4999-8999-999999999999'
      and tenant_id = '44444444-4444-4444-8444-444444444444'
  )
) as security_staging_cross_tenant_fixture;

commit;
