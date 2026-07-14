-- Run against a disposable/local database after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/security_patch_10_customer_consistency.sql

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000101',
   'authenticated', 'authenticated', 'owner-a10@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000102',
   'authenticated', 'authenticated', 'owner-b10@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000103',
   'authenticated', 'authenticated', 'manager-a10@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000104',
   'authenticated', 'authenticated', 'cashier-a10@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000101',
   'Patch 10 Tenant A', 'retail', 2, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000102',
   'Patch 10 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000101',
   'Patch 10 Owner A', 'owner-a10@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000102',
   '00000000-0000-4000-8000-000000000102',
   'Patch 10 Owner B', 'owner-b10@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000103',
   '00000000-0000-4000-8000-000000000101',
   'Patch 10 Manager A', 'manager-a10@example.invalid', 'manager'),
  ('00000000-0000-4000-8000-000000000104',
   '00000000-0000-4000-8000-000000000101',
   'Patch 10 Cashier A', 'cashier-a10@example.invalid', 'cashier');

insert into public.branches (id, tenant_id, name, address, city, is_active) values
  ('00000000-0000-4000-8000-000000000105',
   '00000000-0000-4000-8000-000000000101',
   'Tenant A Branch 1', 'A1 address', 'A city', true),
  ('00000000-0000-4000-8000-000000000106',
   '00000000-0000-4000-8000-000000000101',
   'Tenant A Branch 2', 'A2 address', 'A city', true),
  ('00000000-0000-4000-8000-000000000107',
   '00000000-0000-4000-8000-000000000102',
   'Tenant B Branch', 'B address', 'B city', true);

insert into public.customers (
  id, tenant_id, branch_id, full_name, phone
) values (
  '00000000-0000-4000-8000-000000000109',
  '00000000-0000-4000-8000-000000000102',
  '00000000-0000-4000-8000-000000000107',
  'Tenant B Customer', '03000000109'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000103',
  true
);

-- Manager creates and updates a customer, including movement to another branch
-- in the same tenant. Policies are intentionally role-neutral.
insert into public.customers (
  id, tenant_id, branch_id, full_name, phone
) values (
  '00000000-0000-4000-8000-000000000108',
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000105',
  'Tenant A Customer', '03000000108'
);

update public.customers
set full_name = 'Tenant A Customer Updated',
    branch_id = '00000000-0000-4000-8000-000000000106'
where id = '00000000-0000-4000-8000-000000000108';

do $test$
declare
  visible_count integer;
  affected_count integer;
begin
  select count(*) into visible_count from public.customers;
  if visible_count <> 1 then
    raise exception 'Manager sees % customers; expected one own-tenant customer',
      visible_count;
  end if;

  if not exists (
    select 1 from public.customers
    where id = '00000000-0000-4000-8000-000000000108'
      and branch_id = '00000000-0000-4000-8000-000000000106'
      and full_name = 'Tenant A Customer Updated'
  ) then
    raise exception 'Same-tenant customer create/read/update failed';
  end if;

  begin
    insert into public.customers (
      tenant_id, branch_id, full_name, phone
    ) values (
      '00000000-0000-4000-8000-000000000102',
      '00000000-0000-4000-8000-000000000107',
      'Foreign tenant customer', '03000000110'
    );
    raise exception 'Foreign tenant_id customer insert unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    insert into public.customers (
      tenant_id, branch_id, full_name, phone
    ) values (
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000107',
      'Foreign branch customer', '03000000111'
    );
    raise exception 'Foreign branch_id customer insert unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    update public.customers
    set tenant_id = '00000000-0000-4000-8000-000000000102',
        branch_id = '00000000-0000-4000-8000-000000000107'
    where id = '00000000-0000-4000-8000-000000000108';
    raise exception 'Customer tenant_id reassignment unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    update public.customers
    set branch_id = '00000000-0000-4000-8000-000000000107'
    where id = '00000000-0000-4000-8000-000000000108';
    raise exception 'Foreign branch_id update unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  delete from public.customers
  where id = '00000000-0000-4000-8000-000000000108';
  get diagnostics affected_count = row_count;
  if affected_count <> 0 then
    raise exception 'Customer DELETE unexpectedly succeeded';
  end if;
end
$test$;

-- Owner and cashier retain the same tenant-wide read access.
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000101',
  true
);

do $test$
declare visible_count integer;
begin
  select count(*) into visible_count from public.customers;
  if visible_count <> 1 then
    raise exception 'Owner tenant-wide customer access changed';
  end if;
end
$test$;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000104',
  true
);

do $test$
declare visible_count integer;
begin
  select count(*) into visible_count from public.customers;
  if visible_count <> 1 then
    raise exception 'Cashier tenant-wide customer access changed';
  end if;
end
$test$;

rollback;
