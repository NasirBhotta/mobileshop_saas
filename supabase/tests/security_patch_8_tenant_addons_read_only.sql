-- Run against a disposable/local database after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/security_patch_8_tenant_addons_read_only.sql

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000081',
   'authenticated', 'authenticated', 'owner-a8@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000082',
   'authenticated', 'authenticated', 'owner-b8@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000081',
   'Patch 8 Tenant A', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000082',
   'Patch 8 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000081',
   '00000000-0000-4000-8000-000000000081',
   'Patch 8 Owner A', 'owner-a8@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000082',
   '00000000-0000-4000-8000-000000000082',
   'Patch 8 Owner B', 'owner-b8@example.invalid', 'owner');

-- Backend-managed fixtures for two tenants.
insert into public.tenant_addons (id, tenant_id, addon_key, enabled) values
  ('00000000-0000-4000-8000-000000000083',
   '00000000-0000-4000-8000-000000000081',
   'supplier_procurement', true),
  ('00000000-0000-4000-8000-000000000084',
   '00000000-0000-4000-8000-000000000082',
   'supplier_procurement', true);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000081',
  true
);

do $test$
declare
  visible_count integer;
begin
  select count(*) into visible_count from public.tenant_addons;
  if visible_count <> 1 then
    raise exception 'User can see % tenant add-ons; expected exactly 1 own row',
      visible_count;
  end if;

  if not exists (
    select 1 from public.tenant_addons
    where id = '00000000-0000-4000-8000-000000000083'
  ) then
    raise exception 'User cannot read own tenant add-on';
  end if;

  if exists (
    select 1 from public.tenant_addons
    where id = '00000000-0000-4000-8000-000000000084'
  ) then
    raise exception 'User can read another tenant add-on';
  end if;

  begin
    insert into public.tenant_addons (tenant_id, addon_key, enabled) values (
      '00000000-0000-4000-8000-000000000081', 'client_insert', true
    );
    raise exception 'Client tenant_addons INSERT unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    update public.tenant_addons
    set enabled = false
    where id = '00000000-0000-4000-8000-000000000083';
    raise exception 'Client tenant_addons UPDATE unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    delete from public.tenant_addons
    where id = '00000000-0000-4000-8000-000000000083';
    raise exception 'Client tenant_addons DELETE unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  -- The intentionally disabled package/add-on gate remains disabled.
  if not public.tenant_procurement_enabled(
    '00000000-0000-4000-8000-000000000081'
  ) then
    raise exception 'Procurement is no longer enabled for Tenant A';
  end if;

  if not public.tenant_procurement_enabled(
    '00000000-0000-4000-8000-000000000082'
  ) then
    raise exception 'Procurement is no longer enabled for Tenant B';
  end if;
end
$test$;

reset role;
set local role service_role;

-- Trusted backend retains full add-on management access.
insert into public.tenant_addons (id, tenant_id, addon_key, enabled) values (
  '00000000-0000-4000-8000-000000000085',
  '00000000-0000-4000-8000-000000000081',
  'backend_managed_test',
  true
);

update public.tenant_addons
set enabled = false
where id = '00000000-0000-4000-8000-000000000085';

delete from public.tenant_addons
where id = '00000000-0000-4000-8000-000000000085';

reset role;

rollback;
