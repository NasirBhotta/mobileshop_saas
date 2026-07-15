-- Run against a disposable/local database after applying all migrations.
begin;

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000241',
   'Roles 4 Tenant A', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000242',
   'Roles 4 Tenant B', 'retail', 1, 'starter', 'active', true);

select public.sync_compatibility_system_roles();

-- A tenant custom role must not be populated by the compatibility seed.
insert into public.roles (
  tenant_id, code, name, description, is_system, is_active
) values (
  '00000000-0000-4000-8000-000000000241',
  'auditor', 'Auditor', 'Roles Patch 4 isolation fixture', false, true
);

do $test$
declare
  permission_count_before bigint;
  permission_count_after bigint;
  tenant_id_to_test uuid;
  role_code_to_test text;
begin
  perform public.sync_compatibility_role_permissions();

  select count(*) into permission_count_before
  from public.role_permissions rp
  join public.roles r on r.id = rp.role_id
  where r.tenant_id in (
    '00000000-0000-4000-8000-000000000241',
    '00000000-0000-4000-8000-000000000242'
  );

  perform public.sync_compatibility_role_permissions();

  select count(*) into permission_count_after
  from public.role_permissions rp
  join public.roles r on r.id = rp.role_id
  where r.tenant_id in (
    '00000000-0000-4000-8000-000000000241',
    '00000000-0000-4000-8000-000000000242'
  );

  if permission_count_after <> permission_count_before then
    raise exception 'Repeated role-permission sync changed the matrix row count';
  end if;

  if exists (
    select rp.role_id, rp.permission_id
    from public.role_permissions rp
    group by rp.role_id, rp.permission_id
    having count(*) > 1
  ) then
    raise exception 'Repeated role-permission sync created duplicates';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.roles r on r.id = rp.role_id
    where r.code = 'auditor'
      and r.tenant_id = '00000000-0000-4000-8000-000000000241'
  ) then
    raise exception 'Compatibility seed assigned permissions to a custom role';
  end if;

  foreach tenant_id_to_test in array array[
    '00000000-0000-4000-8000-000000000241'::uuid,
    '00000000-0000-4000-8000-000000000242'::uuid
  ] loop
    foreach role_code_to_test in array array['owner', 'manager', 'cashier'] loop
      -- Expected minus actual must be empty.
      if exists (
        select p.id
        from public.permissions p
        where p.is_active
          and (
            role_code_to_test = 'owner'
            or (
              role_code_to_test = 'manager'
              and p.key not in (
                'report.all_branches.view',
                'customer.credit.update',
                'pos.return.override'
              )
            )
            or (
              role_code_to_test = 'cashier'
              and p.key not in (
                'report.all_branches.view',
                'customer.credit.update',
                'pos.return.override',
                'pos.discount.approve',
                'pos.return.approve'
              )
            )
          )
        except
        select rp.permission_id
        from public.role_permissions rp
        join public.roles r on r.id = rp.role_id
        where r.tenant_id = tenant_id_to_test
          and r.code = role_code_to_test
          and r.is_system
      ) then
        raise exception 'Role % in tenant % is missing intended permissions',
          role_code_to_test, tenant_id_to_test;
      end if;

      -- Actual minus expected must also be empty.
      if exists (
        select rp.permission_id
        from public.role_permissions rp
        join public.roles r on r.id = rp.role_id
        where r.tenant_id = tenant_id_to_test
          and r.code = role_code_to_test
          and r.is_system
        except
        select p.id
        from public.permissions p
        where p.is_active
          and (
            role_code_to_test = 'owner'
            or (
              role_code_to_test = 'manager'
              and p.key not in (
                'report.all_branches.view',
                'customer.credit.update',
                'pos.return.override'
              )
            )
            or (
              role_code_to_test = 'cashier'
              and p.key not in (
                'report.all_branches.view',
                'customer.credit.update',
                'pos.return.override',
                'pos.discount.approve',
                'pos.return.approve'
              )
            )
          )
      ) then
        raise exception 'Role % in tenant % received unintended permissions',
          role_code_to_test, tenant_id_to_test;
      end if;
    end loop;
  end loop;

  if not exists (
    select 1 from public.permissions
    where key = 'pos.return.approve' and is_active
  ) or not exists (
    select 1 from public.permissions
    where key = 'pos.return.override' and is_active
  ) then
    raise exception 'Return approval/override permission keys are missing';
  end if;
end
$test$;

rollback;
