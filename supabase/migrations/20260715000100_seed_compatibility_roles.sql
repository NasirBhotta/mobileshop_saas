-- Roles Patch 2: mirror the current users.role values into the role foundation.
-- public.users.role remains the runtime compatibility source and is not changed.

create or replace function public.sync_compatibility_system_roles()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  unknown_count bigint;
  unknown_values text;
  unknown_sample_ids text;
  pending_tenant_count bigint;
begin
  insert into public.roles (
    tenant_id,
    code,
    name,
    description,
    is_system,
    is_active,
    deleted_at
  )
  select
    t.id,
    seed.code,
    seed.name,
    seed.description,
    true,
    true,
    null
  from public.tenants t
  cross join (
    values
      ('owner', 'Owner', 'Current compatibility owner role'),
      ('manager', 'Manager', 'Current compatibility manager role'),
      ('cashier', 'Cashier', 'Current compatibility cashier role')
  ) as seed(code, name, description)
  on conflict (tenant_id, lower(code)) do update
  set code = excluded.code,
      name = excluded.name,
      description = excluded.description,
      is_system = true,
      is_active = true,
      deleted_at = null;

  insert into public.user_role_assignments (
    tenant_id,
    user_id,
    role_id
  )
  select
    u.tenant_id,
    u.id,
    r.id
  from public.users u
  join public.roles r
    on r.tenant_id = u.tenant_id
   and r.code = u.role
   and r.is_system
   and r.is_active
   and r.deleted_at is null
  where u.tenant_id is not null
    and u.role in ('owner', 'manager', 'cashier')
  on conflict (tenant_id, user_id, role_id)
    where revoked_at is null
  do nothing;

  select count(*)
  into unknown_count
  from public.users u
  where u.role is null
     or u.role not in ('owner', 'manager', 'cashier');

  if unknown_count > 0 then
    select string_agg(role_value, ', ' order by role_value)
    into unknown_values
    from (
      select distinct coalesce(u.role, '<null>') as role_value
      from public.users u
      where u.role is null
         or u.role not in ('owner', 'manager', 'cashier')
      limit 20
    ) values_to_report;

    select string_agg(id::text, ', ' order by id::text)
    into unknown_sample_ids
    from (
      select u.id
      from public.users u
      where u.role is null
         or u.role not in ('owner', 'manager', 'cashier')
      order by u.id
      limit 10
    ) users_to_report;

    raise warning using message = format(
      'Roles Patch 2 skipped %s users with unknown role values [%s]. Sample user IDs: %s',
      unknown_count,
      coalesce(unknown_values, '(none)'),
      coalesce(unknown_sample_ids, '(none)')
    );
  end if;

  select count(*)
  into pending_tenant_count
  from public.users u
  where u.tenant_id is null
    and u.role in ('owner', 'manager', 'cashier');

  if pending_tenant_count > 0 then
    raise notice
      'Roles Patch 2 deferred % known-role users until onboarding assigns tenant_id',
      pending_tenant_count;
  end if;
end
$function$;

revoke all on function public.sync_compatibility_system_roles() from public;
revoke all on function public.sync_compatibility_system_roles() from anon;
revoke all on function public.sync_compatibility_system_roles() from authenticated;

select public.sync_compatibility_system_roles();
