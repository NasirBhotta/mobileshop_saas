-- Run against a disposable/local database after applying all migrations.
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000271',
   'authenticated', 'authenticated', 'owner-a-r7@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000272',
   'authenticated', 'authenticated', 'manager-a-r7@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000273',
   'authenticated', 'authenticated', 'cashier-a-r7@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000274',
   'authenticated', 'authenticated', 'owner-b-r7@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000271',
   'Roles 7 Tenant A', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000274',
   'Roles 7 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000271',
   '00000000-0000-4000-8000-000000000271',
   'Roles 7 Owner A', 'owner-a-r7@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000272',
   '00000000-0000-4000-8000-000000000271',
   'Roles 7 Manager A', 'manager-a-r7@example.invalid', 'manager'),
  ('00000000-0000-4000-8000-000000000273',
   '00000000-0000-4000-8000-000000000271',
   'Roles 7 Cashier A', 'cashier-a-r7@example.invalid', 'cashier'),
  ('00000000-0000-4000-8000-000000000274',
   '00000000-0000-4000-8000-000000000274',
   'Roles 7 Owner B', 'owner-b-r7@example.invalid', 'owner');

select public.sync_compatibility_system_roles();
select public.sync_compatibility_role_permissions();

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000271',
  true
);

do $test$
declare
  custom_role_id uuid;
  replacement_role_id uuid;
  cashier_role_id uuid;
  owner_role_id uuid;
  foreign_owner_role_id uuid;
  moved_count integer;
begin
  custom_role_id := public.create_custom_role(
    'store_lead', 'Store Lead', 'Custom role fixture',
    array['inventory.product.view', 'pos.discount.approve']
  );
  replacement_role_id := public.create_custom_role(
    'floor_staff', 'Floor Staff', null,
    array['inventory.product.view']
  );

  select id into cashier_role_id from public.roles
  where tenant_id = '00000000-0000-4000-8000-000000000271'
    and code = 'cashier';
  select id into owner_role_id from public.roles
  where tenant_id = '00000000-0000-4000-8000-000000000271'
    and code = 'owner';
  select id into foreign_owner_role_id from public.roles
  where tenant_id = '00000000-0000-4000-8000-000000000274'
    and code = 'owner';

  perform public.rename_role(custom_role_id, 'Senior Store Lead', 'Renamed');
  if not exists (
    select 1 from public.roles
    where id = custom_role_id and name = 'Senior Store Lead'
  ) then
    raise exception 'Custom role rename failed';
  end if;

  perform public.update_role_permissions(
    custom_role_id,
    array['inventory.product.view', 'customer.credit.update']
  );
  if (select count(*) from public.role_permissions rp
      join public.permissions p on p.id = rp.permission_id
      where rp.role_id = custom_role_id) <> 2
     or not exists (
       select 1 from public.role_permissions rp
       join public.permissions p on p.id = rp.permission_id
       where rp.role_id = custom_role_id
         and p.key = 'customer.credit.update'
     ) then
    raise exception 'Role permission replacement failed';
  end if;

  begin
    perform public.update_role_permissions(
      custom_role_id, array['permission.does_not.exist']
    );
    raise exception 'Invalid permission assignment unexpectedly succeeded';
  exception when invalid_parameter_value then
    if sqlstate <> '22023' then raise; end if;
  end;

  perform public.assign_user_to_role(
    '00000000-0000-4000-8000-000000000272', custom_role_id
  );
  if not exists (
    select 1 from public.user_role_assignments
    where tenant_id = '00000000-0000-4000-8000-000000000271'
      and user_id = '00000000-0000-4000-8000-000000000272'
      and role_id = custom_role_id and revoked_at is null
  ) then
    raise exception 'Same-tenant role assignment failed';
  end if;

  begin
    perform public.set_role_active(custom_role_id, false);
    raise exception 'Assigned role deactivation unexpectedly succeeded';
  exception when check_violation then
    if sqlstate <> '23514' then raise; end if;
  end;

  moved_count := public.move_role_users(custom_role_id, replacement_role_id);
  if moved_count <> 1 then
    raise exception 'Expected one moved user, got %', moved_count;
  end if;
  perform public.set_role_active(custom_role_id, false);
  if (select is_active from public.roles where id = custom_role_id) then
    raise exception 'Unassigned custom role was not deactivated';
  end if;

  begin
    perform public.assign_user_to_role(
      '00000000-0000-4000-8000-000000000273', custom_role_id
    );
    raise exception 'Inactive role assignment unexpectedly succeeded';
  exception when check_violation then
    if sqlstate <> '23514' then raise; end if;
  end;

  perform public.set_role_active(custom_role_id, true);
  if not (select is_active from public.roles where id = custom_role_id) then
    raise exception 'Custom role reactivation failed';
  end if;

  begin
    perform public.set_role_active(owner_role_id, false);
    raise exception 'Owner role deactivation unexpectedly succeeded';
  exception when check_violation then
    if sqlstate <> '23514' then raise; end if;
  end;

  begin
    perform public.update_role_permissions(owner_role_id, array[]::text[]);
    raise exception 'Owner role-management permission removal unexpectedly succeeded';
  exception when check_violation then
    if sqlstate <> '23514' then raise; end if;
  end;

  begin
    perform public.assign_user_to_role(
      '00000000-0000-4000-8000-000000000271', cashier_role_id
    );
    raise exception 'Last active owner reassignment unexpectedly succeeded';
  exception when check_violation then
    if sqlstate <> '23514' then raise; end if;
  end;

  begin
    perform public.rename_role(foreign_owner_role_id, 'Cross tenant', null);
    raise exception 'Cross-tenant role rename unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    perform public.assign_user_to_role(
      '00000000-0000-4000-8000-000000000274', replacement_role_id
    );
    raise exception 'Cross-tenant user assignment unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  if (select count(*) from public.role_management_audit_log
      where tenant_id = '00000000-0000-4000-8000-000000000271') < 8 then
    raise exception 'Role management changes were not fully audited';
  end if;

  -- Preserve the compatibility source throughout role management.
  if (select role from public.users
      where id = '00000000-0000-4000-8000-000000000272') <> 'manager' then
    raise exception 'Legacy users.role was modified';
  end if;
end
$test$;

-- A user without user.role.manage cannot invoke management RPCs.
reset role;
insert into public.roles (
  tenant_id, code, name, is_system, is_active
) values (
  '00000000-0000-4000-8000-000000000271',
  'no_role_admin', 'No Role Admin', false, true
);
set local role authenticated;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000273',
  true
);

select public.assign_user_to_role(
  '00000000-0000-4000-8000-000000000273',
  (select id from public.roles
   where tenant_id = '00000000-0000-4000-8000-000000000271'
     and code = 'no_role_admin')
);

do $test$
begin
  begin
    perform public.create_custom_role('blocked_role', 'Blocked Role');
    raise exception 'User without role-management permission unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;
end
$test$;

rollback;
