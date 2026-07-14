-- Run against a disposable/local database after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/security_patch_6_branches_rls.sql

begin;

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
   '00000000-0000-4000-8000-000000000061',
   'authenticated', 'authenticated', 'owner-a6@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000062',
   'authenticated', 'authenticated', 'owner-b6@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000063',
   'authenticated', 'authenticated', 'manager-a6@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000061',
   'Patch 6 Tenant A', 'retail', 3, 'starter', 'active', false),
  ('00000000-0000-4000-8000-000000000062',
   'Patch 6 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000061',
   '00000000-0000-4000-8000-000000000061',
   'Patch 6 Owner A', 'owner-a6@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000062',
   '00000000-0000-4000-8000-000000000062',
   'Patch 6 Owner B', 'owner-b6@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000063',
   '00000000-0000-4000-8000-000000000061',
   'Patch 6 Manager A', 'manager-a6@example.invalid', 'manager');

-- A branch belonging to another tenant exists but must remain invisible.
insert into public.branches (
  id, tenant_id, name, address, city, is_active
) values (
  '00000000-0000-4000-8000-000000000069',
  '00000000-0000-4000-8000-000000000062',
  'Tenant B Branch', 'B address', 'B city', true
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000061',
  true
);

-- Current onboarding creates branches after users.tenant_id has been linked.
insert into public.branches (
  id, tenant_id, name, address, city, is_active
) values
  ('00000000-0000-4000-8000-000000000064',
   '00000000-0000-4000-8000-000000000061',
   'Tenant A Branch 1', 'A1 address', 'A city', true),
  ('00000000-0000-4000-8000-000000000065',
   '00000000-0000-4000-8000-000000000061',
   'Tenant A Branch 2', 'A2 address', 'A city', true);

do $test$
declare
  visible_count integer;
  affected_count integer;
begin
  select count(*) into visible_count from public.branches;
  if visible_count <> 2 then
    raise exception 'Owner can see % branches; expected 2 own-tenant branches',
      visible_count;
  end if;

  update public.branches
  set name = 'Tenant A Branch 1 updated',
      address = 'Updated address',
      city = 'Updated city'
  where id = '00000000-0000-4000-8000-000000000064';
  get diagnostics affected_count = row_count;
  if affected_count <> 1 then
    raise exception 'Own-tenant branch update affected % rows', affected_count;
  end if;

  update public.users
  set branch_id = '00000000-0000-4000-8000-000000000064'
  where id = auth.uid();
  get diagnostics affected_count = row_count;
  if affected_count <> 1 then
    raise exception 'First own-tenant branch selection failed';
  end if;

  update public.users
  set branch_id = '00000000-0000-4000-8000-000000000065'
  where id = auth.uid();
  get diagnostics affected_count = row_count;
  if affected_count <> 1 then
    raise exception 'Switching to second own-tenant branch failed';
  end if;

  update public.branches
  set name = 'Cross-tenant update'
  where id = '00000000-0000-4000-8000-000000000069';
  get diagnostics affected_count = row_count;
  if affected_count <> 0 then
    raise exception 'Cross-tenant branch update unexpectedly affected a row';
  end if;

  delete from public.branches
  where id = '00000000-0000-4000-8000-000000000064';
  get diagnostics affected_count = row_count;
  if affected_count <> 0 then
    raise exception 'Client branch DELETE unexpectedly affected a row';
  end if;

  begin
    insert into public.branches (
      id, tenant_id, name, address, city, is_active
    ) values (
      '00000000-0000-4000-8000-000000000068',
      '00000000-0000-4000-8000-000000000062',
      'Cross-tenant insert', 'Cross address', 'Cross city', true
    );
    raise exception 'Cross-tenant branch insert unexpectedly succeeded';
  exception
    when insufficient_privilege then
      if sqlstate <> '42501' then
        raise;
      end if;
  end;
end
$test$;

-- Tenant-wide behaviour is role-neutral: a manager in the same tenant can
-- read, insert, update, and select branches belonging to that tenant.
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000063',
  true
);

insert into public.branches (
  id, tenant_id, name, address, city, is_active
) values (
  '00000000-0000-4000-8000-000000000066',
  '00000000-0000-4000-8000-000000000061',
  'Manager-created branch', 'Manager address', 'A city', true
);

update public.branches
set name = 'Manager-updated branch'
where id = '00000000-0000-4000-8000-000000000066';

update public.users
set branch_id = '00000000-0000-4000-8000-000000000065'
where id = auth.uid();

do $test$
declare
  visible_count integer;
begin
  select count(*) into visible_count from public.branches;
  if visible_count <> 3 then
    raise exception 'Manager can see % branches; expected 3 own-tenant branches',
      visible_count;
  end if;
end
$test$;

rollback;
