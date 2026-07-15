-- Run against a disposable/local database after applying all migrations.
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000211',
   'authenticated', 'authenticated', 'owner-a-r2@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000212',
   'authenticated', 'authenticated', 'manager-a-r2@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000213',
   'authenticated', 'authenticated', 'cashier-a-r2@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000214',
   'authenticated', 'authenticated', 'owner-b-r2@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000215',
   'authenticated', 'authenticated', 'unknown-a-r2@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000211',
   'Roles 2 Tenant A', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000214',
   'Roles 2 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000211',
   '00000000-0000-4000-8000-000000000211',
   'Roles 2 Owner A', 'owner-a-r2@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000212',
   '00000000-0000-4000-8000-000000000211',
   'Roles 2 Manager A', 'manager-a-r2@example.invalid', 'manager'),
  ('00000000-0000-4000-8000-000000000213',
   '00000000-0000-4000-8000-000000000211',
   'Roles 2 Cashier A', 'cashier-a-r2@example.invalid', 'cashier'),
  ('00000000-0000-4000-8000-000000000214',
   '00000000-0000-4000-8000-000000000214',
   'Roles 2 Owner B', 'owner-b-r2@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000215',
   '00000000-0000-4000-8000-000000000211',
   'Roles 2 Unknown A', 'unknown-a-r2@example.invalid', 'auditor');

do $test$
declare
  duplicate_count integer;
  valid_assignment_count integer;
  permission_count_before bigint;
  role_permission_count_before bigint;
begin
  select count(*) into permission_count_before from public.permissions;
  select count(*) into role_permission_count_before
  from public.role_permissions;

  -- Run twice in this same transaction block: the second call must not create
  -- role or assignment duplicates, or modify either permission table.
  perform public.sync_compatibility_system_roles();
  perform public.sync_compatibility_system_roles();

  if (select count(*) from public.roles
      where tenant_id in (
        '00000000-0000-4000-8000-000000000211',
        '00000000-0000-4000-8000-000000000214'
      )
        and code in ('owner', 'manager', 'cashier')
        and is_system and is_active and deleted_at is null) <> 6 then
    raise exception 'Every tenant did not receive three active system roles';
  end if;

  select count(*) into valid_assignment_count
  from public.user_role_assignments a
  join public.roles r on r.id = a.role_id
  join public.users u on u.id = a.user_id
  where u.id in (
    '00000000-0000-4000-8000-000000000211',
    '00000000-0000-4000-8000-000000000212',
    '00000000-0000-4000-8000-000000000213',
    '00000000-0000-4000-8000-000000000214'
  )
    and a.revoked_at is null
    and r.code = u.role
    and r.tenant_id = u.tenant_id;

  if valid_assignment_count <> 4 then
    raise exception 'Not every valid compatibility user received its role';
  end if;

  select count(*) into duplicate_count
  from (
    select tenant_id, code
    from public.roles
    group by tenant_id, code
    having count(*) > 1
  ) duplicates;
  if duplicate_count <> 0 then
    raise exception 'Repeated sync created duplicate roles';
  end if;

  select count(*) into duplicate_count
  from (
    select tenant_id, user_id, role_id
    from public.user_role_assignments
    where revoked_at is null
    group by tenant_id, user_id, role_id
    having count(*) > 1
  ) duplicates;
  if duplicate_count <> 0 then
    raise exception 'Repeated sync created duplicate assignments';
  end if;

  if exists (
    select 1 from public.user_role_assignments
    where user_id = '00000000-0000-4000-8000-000000000215'
  ) then
    raise exception 'Unknown role user was silently assigned';
  end if;

  if (select role from public.users
      where id = '00000000-0000-4000-8000-000000000215') <> 'auditor' then
    raise exception 'Unknown users.role compatibility value was modified';
  end if;

  if (select count(*) from public.permissions) <> permission_count_before
     or (select count(*) from public.role_permissions) <>
       role_permission_count_before then
    raise exception 'Roles Patch 2 changed permissions or role_permissions';
  end if;

  begin
    insert into public.user_role_assignments (
      tenant_id, user_id, role_id
    )
    select
      '00000000-0000-4000-8000-000000000214',
      '00000000-0000-4000-8000-000000000211',
      r.id
    from public.roles r
    where r.tenant_id = '00000000-0000-4000-8000-000000000214'
      and r.code = 'owner';
    raise exception 'Cross-tenant compatibility assignment unexpectedly succeeded';
  exception when check_violation then
    if sqlstate <> '23514' then raise; end if;
  end;
end
$test$;

rollback;
