-- Run against a disposable/local database after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/security_patch_5_tenants_rls.sql

begin;

-- public.users.id references auth.users.id, so create disposable Auth identities
-- before their matching public profiles.
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000051',
   'authenticated', 'authenticated', 'owner-a@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000052',
   'authenticated', 'authenticated', 'manager-a@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000053',
   'authenticated', 'authenticated', 'cashier-a@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000054',
   'authenticated', 'authenticated', 'owner-b@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

-- Onboarding creates the public owner profile before it creates the tenant.
insert into public.users (id, tenant_id, full_name, email, role) values (
  '00000000-0000-4000-8000-000000000051',
  null,
  'Owner A',
  'owner-a@example.invalid',
  'owner'
);

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values (
  '00000000-0000-4000-8000-000000000054',
  'Tenant B', 'retail', 1, 'starter', 'active', true
);

insert into public.users (id, tenant_id, full_name, email, role) values (
  '00000000-0000-4000-8000-000000000054',
  '00000000-0000-4000-8000-000000000054',
  'Owner B',
  'owner-b@example.invalid',
  'owner'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000051',
  true
);

-- Authenticated onboarding creates only the caller's initial starter tenant.
insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values (
  '00000000-0000-4000-8000-000000000051',
  'Tenant A', 'retail', 1, 'starter', 'active', false
);

-- Interrupted onboarding may safely retry its upsert before users.tenant_id is
-- linked. Unchanged plan/status also remains compatible with Security Patch 4.
insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values (
  '00000000-0000-4000-8000-000000000051',
  'Tenant A retry', 'mobile_shop', 2, 'starter', 'active', false
)
on conflict (id) do update set
  shop_name = excluded.shop_name,
  business_type = excluded.business_type,
  branch_count = excluded.branch_count,
  plan = excluded.plan,
  status = excluded.status,
  setup_complete = excluded.setup_complete;

reset role;
update public.users
set tenant_id = '00000000-0000-4000-8000-000000000051'
where id = '00000000-0000-4000-8000-000000000051';

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000052',
   '00000000-0000-4000-8000-000000000051',
   'Manager A', 'manager-a@example.invalid', 'manager'),
  ('00000000-0000-4000-8000-000000000053',
   '00000000-0000-4000-8000-000000000051',
   'Cashier A', 'cashier-a@example.invalid', 'cashier');

set local role authenticated;

do $test$
declare
  visible_count integer;
  affected_count integer;
begin
  select count(*) into visible_count from public.tenants;
  if visible_count <> 1 then
    raise exception 'Owner can see % tenants; expected exactly 1', visible_count;
  end if;

  update public.tenants
  set shop_name = 'Tenant A updated',
      business_type = 'mobile_shop',
      branch_count = 3,
      setup_complete = true
  where id = '00000000-0000-4000-8000-000000000051';
  get diagnostics affected_count = row_count;
  if affected_count <> 1 then
    raise exception 'Owner allowed-field update affected % rows', affected_count;
  end if;

  begin
    update public.tenants
    set plan = 'business'
    where id = '00000000-0000-4000-8000-000000000051';
    raise exception 'Owner plan update unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;

  begin
    update public.tenants
    set status = 'suspended'
    where id = '00000000-0000-4000-8000-000000000051';
    raise exception 'Owner status update unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;

  update public.tenants
  set shop_name = 'Cross tenant update'
  where id = '00000000-0000-4000-8000-000000000054';
  get diagnostics affected_count = row_count;
  if affected_count <> 0 then
    raise exception 'Cross-tenant update unexpectedly affected a row';
  end if;

  delete from public.tenants
  where id = '00000000-0000-4000-8000-000000000051';
  get diagnostics affected_count = row_count;
  if affected_count <> 0 then
    raise exception 'Client DELETE unexpectedly affected a row';
  end if;
end
$test$;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000052',
  true
);

do $test$
declare affected_count integer;
begin
  update public.tenants
  set shop_name = 'Manager update'
  where id = '00000000-0000-4000-8000-000000000051';
  get diagnostics affected_count = row_count;
  if affected_count <> 0 then
    raise exception 'Manager tenant update unexpectedly affected a row';
  end if;
end
$test$;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000053',
  true
);

do $test$
declare affected_count integer;
begin
  update public.tenants
  set shop_name = 'Cashier update'
  where id = '00000000-0000-4000-8000-000000000051';
  get diagnostics affected_count = row_count;
  if affected_count <> 0 then
    raise exception 'Cashier tenant update unexpectedly affected a row';
  end if;
end
$test$;

rollback;
