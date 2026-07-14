-- Run against a disposable/local database after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/security_patch_4_tenant_plan_status.sql

begin;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000004',
  true
);
select set_config('request.jwt.claim.user_role', 'owner', true);

-- Current onboarding creates starter/active tenants as an authenticated user.
insert into public.tenants (
  id,
  shop_name,
  business_type,
  branch_count,
  plan,
  status,
  setup_complete
) values (
  '00000000-0000-4000-8000-000000000004',
  'Security Patch 4 fixture',
  'retail',
  1,
  'starter',
  'active',
  false
);

-- Owner-permitted tenant fields and the current onboarding completion update
-- continue to work. All application roles use this same authenticated DB role.
update public.tenants
set shop_name = 'Updated fixture',
    business_type = 'mobile_shop',
    branch_count = 2,
    setup_complete = true
where id = '00000000-0000-4000-8000-000000000004';

do $test$
begin
  if not exists (
    select 1
    from public.tenants
    where id = '00000000-0000-4000-8000-000000000004'
      and shop_name = 'Updated fixture'
      and business_type = 'mobile_shop'
      and branch_count = 2
      and setup_complete
  ) then
    raise exception 'Allowed tenant fields were not updated';
  end if;

  begin
    update public.tenants
    set plan = 'business'
    where id = '00000000-0000-4000-8000-000000000004';
    raise exception 'Authenticated plan update unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;

  begin
    update public.tenants
    set status = 'suspended'
    where id = '00000000-0000-4000-8000-000000000004';
    raise exception 'Authenticated status update unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;

  -- An unchanged subscription payload is valid, preserving onboarding upsert
  -- conflict behaviour without permitting a subscription-state mutation.
  update public.tenants
  set plan = 'starter', status = 'active', setup_complete = true
  where id = '00000000-0000-4000-8000-000000000004';
end
$test$;

select set_config('request.jwt.claim.user_role', 'manager', true);

do $test$
begin
  begin
    update public.tenants
    set plan = 'business'
    where id = '00000000-0000-4000-8000-000000000004';
    raise exception 'Manager plan update unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;
end
$test$;

select set_config('request.jwt.claim.user_role', 'cashier', true);

do $test$
begin
  begin
    update public.tenants
    set status = 'suspended'
    where id = '00000000-0000-4000-8000-000000000004';
    raise exception 'Cashier status update unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;
end
$test$;

reset role;
set local role service_role;

-- Trusted backend path remains available for future billing operations.
update public.tenants
set plan = 'business', status = 'suspended'
where id = '00000000-0000-4000-8000-000000000004';

reset role;

do $test$
begin
  if not exists (
    select 1
    from public.tenants
    where id = '00000000-0000-4000-8000-000000000004'
      and plan = 'business'
      and status = 'suspended'
  ) then
    raise exception 'Trusted subscription update was blocked';
  end if;
end
$test$;

rollback;
