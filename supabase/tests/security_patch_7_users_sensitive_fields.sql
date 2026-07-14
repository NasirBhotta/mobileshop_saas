-- Run against a disposable/local database after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/security_patch_7_users_sensitive_fields.sql

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000071',
   'authenticated', 'authenticated', 'owner-a7@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000072',
   'authenticated', 'authenticated', 'owner-b7@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000071',
  true
);

-- Exact initial profile shape used by current email/OAuth onboarding.
insert into public.users (
  id, full_name, email, phone, role
) values (
  '00000000-0000-4000-8000-000000000071',
  'Patch 7 Owner A',
  'owner-a7@example.invalid',
  '03000000000',
  'owner'
);

reset role;

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000071',
   'Patch 7 Tenant A', 'retail', 2, 'starter', 'active', false),
  ('00000000-0000-4000-8000-000000000072',
   'Patch 7 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.branches (
  id, tenant_id, name, address, city, is_active
) values
  ('00000000-0000-4000-8000-000000000073',
   '00000000-0000-4000-8000-000000000071',
   'Tenant A Branch 1', 'A1 address', 'A city', true),
  ('00000000-0000-4000-8000-000000000074',
   '00000000-0000-4000-8000-000000000071',
   'Tenant A Branch 2', 'A2 address', 'A city', true),
  ('00000000-0000-4000-8000-000000000075',
   '00000000-0000-4000-8000-000000000072',
   'Tenant B Branch', 'B address', 'B city', true);

set local role authenticated;

-- Existing onboarding links NULL to the owner's same-ID incomplete tenant.
update public.users
set tenant_id = '00000000-0000-4000-8000-000000000071'
where id = auth.uid();

-- Normal account profile fields remain client-editable.
update public.users
set full_name = 'Patch 7 Updated Owner',
    email = 'owner-a7-updated@example.invalid',
    phone = '03111111111'
where id = auth.uid();

-- Tenant-wide branch switching remains available.
update public.users
set branch_id = '00000000-0000-4000-8000-000000000073'
where id = auth.uid();

update public.users
set branch_id = '00000000-0000-4000-8000-000000000074'
where id = auth.uid();

do $test$
begin
  if not exists (
    select 1
    from public.users
    where id = auth.uid()
      and full_name = 'Patch 7 Updated Owner'
      and email = 'owner-a7-updated@example.invalid'
      and phone = '03111111111'
      and branch_id = '00000000-0000-4000-8000-000000000074'
  ) then
    raise exception 'Allowed profile or same-tenant branch update failed';
  end if;

  begin
    update public.users set role = 'manager' where id = auth.uid();
    raise exception 'Self role update unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    update public.users
    set tenant_id = '00000000-0000-4000-8000-000000000072'
    where id = auth.uid();
    raise exception 'Self tenant_id update unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    update public.users set tenant_id = null where id = auth.uid();
    raise exception 'Self tenant_id clear unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    update public.users set approval_pin = '1234' where id = auth.uid();
    raise exception 'Self approval_pin update unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    update public.users
    set branch_id = '00000000-0000-4000-8000-000000000075'
    where id = auth.uid();
    raise exception 'Cross-tenant branch selection unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;
end
$test$;

-- A second authenticated user cannot self-create a privileged or pre-assigned
-- profile during onboarding.
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000072',
  true
);

do $test$
begin
  begin
    insert into public.users (
      id, tenant_id, full_name, email, role
    ) values (
      auth.uid(),
      '00000000-0000-4000-8000-000000000072',
      'Invalid preassigned user',
      'invalid-owner-b7@example.invalid',
      'manager'
    );
    raise exception 'Arbitrary onboarding role/tenant insert unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;
end
$test$;

rollback;
