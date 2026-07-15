-- Run against a disposable/local database after applying all migrations.
begin;

do $test$
declare
  permission_count_before integer;
  permission_count_after integer;
  role_permission_count_before bigint;
  expected_modules constant text[] := array[
    'dashboard', 'branches', 'users', 'inventory', 'pos', 'customers',
    'repairs', 'suppliers', 'purchases', 'expenses', 'accounts', 'reports',
    'settings', 'receipts'
  ];
  module_name text;
begin
  select count(*) into permission_count_before from public.permissions;
  select count(*) into role_permission_count_before
  from public.role_permissions;

  perform public.sync_global_permission_catalog();
  select count(*) into permission_count_after from public.permissions;
  perform public.sync_global_permission_catalog();

  if (select count(*) from public.permissions) <> permission_count_after
     or permission_count_after <> permission_count_before then
    raise exception 'Repeated permission catalog sync created duplicates';
  end if;

  if exists (
    select key
    from public.permissions
    group by key
    having count(*) > 1
  ) then
    raise exception 'Permission keys are not unique';
  end if;

  if exists (
    select 1
    from public.permissions
    where key !~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
  ) then
    raise exception 'A permission key violates module.resource.action convention';
  end if;

  foreach module_name in array expected_modules loop
    if not exists (
      select 1 from public.permissions
      where module = module_name and is_active
    ) then
      raise exception 'Permission module % was not seeded', module_name;
    end if;
  end loop;

  if not exists (
    select 1 from public.permissions
    where key = 'inventory.product.view'
      and module = 'inventory'
      and action = 'view'
      and name is not null
      and description is not null
      and is_active
  ) or not exists (
    select 1 from public.permissions
    where key = 'inventory.product.create' and is_active
  ) or not exists (
    select 1 from public.permissions
    where key = 'inventory.stock.adjust' and is_active
  ) or not exists (
    select 1 from public.permissions
    where key = 'pos.sale.create' and is_active
  ) or not exists (
    select 1 from public.permissions
    where key = 'pos.discount.approve' and is_active
  ) or not exists (
    select 1 from public.permissions
    where key = 'report.all_branches.view' and is_active
  ) then
    raise exception 'Required stable permission keys are missing';
  end if;

  if (select count(*) from public.role_permissions) <>
       role_permission_count_before then
    raise exception 'Roles Patch 3 assigned permissions to roles';
  end if;
end
$test$;

rollback;
