-- Run after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/admin_portal_patch_1_platform_admins.sql

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000411',
   'authenticated', 'authenticated', 'active-admin-ap1@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000412',
   'authenticated', 'authenticated', 'inactive-admin-ap1@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000413',
   'authenticated', 'authenticated', 'ordinary-user-ap1@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.platform_admins (user_id, is_active) values
  ('00000000-0000-4000-8000-000000000411', true),
  ('00000000-0000-4000-8000-000000000412', false);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000411',
  true
);

do $test$
begin
  if not public.is_active_platform_admin() then
    raise exception 'Active platform admin verification failed';
  end if;
  if (select count(*) from public.platform_admins) <> 1 then
    raise exception 'Platform admin can read memberships other than its own';
  end if;

  begin
    insert into public.platform_admins (user_id)
    values ('00000000-0000-4000-8000-000000000413');
    raise exception 'Authenticated client created a platform admin';
  exception when insufficient_privilege then null;
  end;
end
$test$;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000412',
  true
);

do $test$
begin
  if public.is_active_platform_admin() then
    raise exception 'Inactive platform admin was accepted';
  end if;
  begin
    update public.platform_admins set is_active = true;
    raise exception 'Inactive admin reactivated itself';
  exception when insufficient_privilege then null;
  end;
end
$test$;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000413',
  true
);

do $test$
begin
  if public.is_active_platform_admin() then
    raise exception 'Ordinary authenticated user was accepted';
  end if;
  if exists (select 1 from public.platform_admins) then
    raise exception 'Ordinary user read a platform admin membership';
  end if;
end
$test$;

reset role;

do $test$
begin
  if has_table_privilege('anon', 'public.platform_admins', 'SELECT')
     or has_function_privilege(
       'anon', 'public.is_active_platform_admin()', 'EXECUTE'
     ) then
    raise exception 'Anonymous platform-admin access remains';
  end if;
  if not has_table_privilege(
    'service_role', 'public.platform_admins', 'INSERT,UPDATE,DELETE'
  ) then
    raise exception 'Trusted backend cannot manage platform admins';
  end if;
end
$test$;

rollback;
