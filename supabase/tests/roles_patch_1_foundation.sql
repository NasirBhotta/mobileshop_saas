-- Run against a disposable/local database after applying all migrations.
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000201',
   'authenticated', 'authenticated', 'owner-a-r1@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000202',
   'authenticated', 'authenticated', 'owner-b-r1@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000201',
   'Roles Tenant A', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000202',
   'Roles Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000201',
   '00000000-0000-4000-8000-000000000201',
   'Roles Owner A', 'owner-a-r1@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000202',
   '00000000-0000-4000-8000-000000000202',
   'Roles Owner B', 'owner-b-r1@example.invalid', 'owner');

insert into public.permissions (id, key, module, action, description) values
  ('00000000-0000-4000-8000-000000000203',
   'test.inventory.read', 'inventory', 'read', 'Test permission');

insert into public.roles (id, tenant_id, code, name) values
  ('00000000-0000-4000-8000-000000000204',
   '00000000-0000-4000-8000-000000000201', 'custom', 'Tenant A Custom'),
  ('00000000-0000-4000-8000-000000000205',
   '00000000-0000-4000-8000-000000000202', 'custom', 'Tenant B Custom');

insert into public.role_permissions (role_id, permission_id) values
  ('00000000-0000-4000-8000-000000000204',
   '00000000-0000-4000-8000-000000000203'),
  ('00000000-0000-4000-8000-000000000205',
   '00000000-0000-4000-8000-000000000203');

insert into public.user_role_assignments (
  id, tenant_id, user_id, role_id
) values (
  '00000000-0000-4000-8000-000000000207',
  '00000000-0000-4000-8000-000000000202',
  '00000000-0000-4000-8000-000000000202',
  '00000000-0000-4000-8000-000000000205'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000201',
  true
);

do $test$
declare visible_count integer;
begin
  select count(*) into visible_count from public.roles;
  if visible_count <> 1 then
    raise exception 'Tenant role isolation failed';
  end if;

  select count(*) into visible_count from public.role_permissions;
  if visible_count <> 1 then
    raise exception 'Role-permission tenant isolation failed';
  end if;

  begin
    insert into public.roles (tenant_id, code, name) values (
      '00000000-0000-4000-8000-000000000201', 'CUSTOM', 'Duplicate code'
    );
    raise exception 'Duplicate role code unexpectedly succeeded';
  exception when unique_violation then
    if sqlstate <> '23505' then raise; end if;
  end;

  insert into public.user_role_assignments (
    id, tenant_id, user_id, role_id
  ) values (
    '00000000-0000-4000-8000-000000000206',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000204'
  );

  select count(*) into visible_count from public.user_role_assignments;
  if visible_count <> 1 then
    raise exception 'User-role assignment tenant isolation failed';
  end if;
end
$test$;

reset role;

do $test$
begin
  begin
    insert into public.user_role_assignments (
      tenant_id, user_id, role_id
    ) values (
      '00000000-0000-4000-8000-000000000202',
      '00000000-0000-4000-8000-000000000201',
      '00000000-0000-4000-8000-000000000205'
    );
    raise exception 'Cross-tenant user-role assignment unexpectedly succeeded';
  exception when check_violation then
    if sqlstate <> '23514' then raise; end if;
  end;
end
$test$;

update public.roles
set is_active = false, deleted_at = now()
where id = '00000000-0000-4000-8000-000000000204';

do $test$
begin
  if not exists (
    select 1
    from public.user_role_assignments a
    join public.roles r on r.id = a.role_id
    where a.id = '00000000-0000-4000-8000-000000000206'
      and not r.is_active
      and r.deleted_at is not null
  ) then
    raise exception 'Historical assignment was not retained';
  end if;

  begin
    insert into public.user_role_assignments (
      tenant_id, user_id, role_id
    ) values (
      '00000000-0000-4000-8000-000000000201',
      '00000000-0000-4000-8000-000000000201',
      '00000000-0000-4000-8000-000000000204'
    );
    raise exception 'Assignment to inactive/deleted role unexpectedly succeeded';
  exception when check_violation then
    if sqlstate <> '23514' then raise; end if;
  end;
end
$test$;

rollback;
