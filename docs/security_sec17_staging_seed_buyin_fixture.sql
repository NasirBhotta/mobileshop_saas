-- SEC-17 staging-only synthetic fixture for commit_customer_buyin_v2 tests.
-- Prerequisite: create an Auth user in the STAGING dashboard with:
--   email:    sec17.staging.owner@gmail.com
--   password: choose a temporary test-only password
--   auto-confirm: enabled
-- This script creates no Auth user and touches no production project.

begin;

do $fixture$
declare
  v_user_id uuid;
  v_plan_id constant uuid := '00000000-0000-4000-8000-000000000001';
  v_tenant_id constant uuid := '11111111-1111-4111-8111-111111111111';
  v_branch_id constant uuid := '22222222-2222-4222-8222-222222222222';
  v_account_id constant uuid := '33333333-3333-4333-8333-333333333333';
begin
  select id into v_user_id
  from auth.users
  where email = 'sec17.staging.owner@gmail.com'
  limit 1;

  if v_user_id is null then
    raise exception using
      errcode = '22023',
      message = 'Create and auto-confirm sec17.staging.owner@gmail.com in STAGING Auth first.';
  end if;

  -- A schema-only clone has no package rows. The tenant trigger requires an
  -- active plan matching tenants.plan before it permits tenant creation.
  insert into public.plans (id, key, name, description, is_active, deleted_at)
  values (
    v_plan_id, 'starter', 'SEC-17 Staging Starter',
    'Synthetic plan used only by SEC-17 staging fixtures.', true, null
  )
  on conflict (id) do update
  set name = excluded.name,
      is_active = true,
      deleted_at = null;

  insert into public.tenants (
    id, shop_name, business_type, branch_count, plan, status, setup_complete
  ) values (
    v_tenant_id, 'SEC-17 Staging Shop', 'mobile_retail', 1, 'starter', 'active', true
  )
  on conflict (id) do update
  set shop_name = excluded.shop_name,
      status = excluded.status,
      setup_complete = excluded.setup_complete;

  insert into public.branches (id, tenant_id, name, address, city, is_active)
  values (v_branch_id, v_tenant_id, 'SEC-17 Test Branch', 'Synthetic only', 'Staging', true)
  on conflict (id) do update
  set tenant_id = excluded.tenant_id,
      is_active = true;

  -- Owner role deliberately exercises the RPC's active-actor/branch checks
  -- while retaining all required permissions for a positive-path test.
  insert into public.users (
    id, tenant_id, branch_id, full_name, email, role, is_active, deleted_at
  ) values (
    v_user_id, v_tenant_id, v_branch_id, 'SEC-17 Staging Owner',
    'sec17.staging.owner@gmail.com', 'owner', true, null
  )
  on conflict (id) do update
  set tenant_id = excluded.tenant_id,
      branch_id = excluded.branch_id,
      full_name = excluded.full_name,
      email = excluded.email,
      role = 'owner',
      is_active = true,
      deleted_at = null;

  insert into public.accounts (
    id, tenant_id, branch_id, name, account_type, opening_balance,
    current_balance, is_default, is_active, note, created_by
  ) values (
    v_account_id, v_tenant_id, v_branch_id, 'SEC-17 Test Cash', 'cash',
    50000, 50000, true, true, 'Synthetic staging account', v_user_id
  )
  on conflict (id) do update
  set current_balance = excluded.current_balance,
      is_active = true,
      note = excluded.note;
end;
$fixture$;

commit;

select
  tenant.id as tenant_id,
  branch.id as branch_id,
  account.id as payment_account_id,
  account.current_balance
from public.tenants tenant
join public.branches branch on branch.tenant_id = tenant.id
join public.accounts account on account.branch_id = branch.id
where tenant.id = '11111111-1111-4111-8111-111111111111';

