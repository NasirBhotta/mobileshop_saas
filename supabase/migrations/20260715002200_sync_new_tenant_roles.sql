-- Role compatibility seeds originally ran once during migration. Tenants and
-- users created afterwards therefore had no database role assignment and the
-- Roles & Permissions settings section was hidden. Repair existing rows and
-- keep future compatibility users synchronized.

select public.sync_compatibility_system_roles();
select public.sync_compatibility_role_permissions();

create or replace function public.ensure_compatibility_user_role()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  target_role_id uuid;
begin
  if new.tenant_id is null
     or new.role not in ('owner', 'manager', 'cashier') then
    return new;
  end if;

  insert into public.roles (
    tenant_id, code, name, description, is_system, is_active, deleted_at
  )
  select
    new.tenant_id,
    seed.code,
    seed.name,
    seed.description,
    true,
    true,
    null
  from (
    values
      ('owner', 'Owner', 'Current compatibility owner role'),
      ('manager', 'Manager', 'Current compatibility manager role'),
      ('cashier', 'Cashier', 'Current compatibility cashier role')
  ) as seed(code, name, description)
  on conflict (tenant_id, lower(code)) do update
  set name = excluded.name,
      description = excluded.description,
      is_system = true,
      is_active = true,
      deleted_at = null;

  -- Mirror the current compatibility permission rules for this tenant's
  -- system roles. Explicit exclusions remain the same as Patch 4.
  insert into public.role_permissions (role_id, permission_id)
  select r.id, p.id
  from public.roles r
  cross join public.permissions p
  where r.tenant_id = new.tenant_id
    and r.is_system
    and r.is_active
    and r.deleted_at is null
    and r.code in ('owner', 'manager', 'cashier')
    and p.is_active
    and (
      r.code = 'owner'
      or (
        r.code = 'manager'
        and p.key not in (
          'report.all_branches.view',
          'customer.credit.update',
          'pos.return.override'
        )
      )
      or (
        r.code = 'cashier'
        and p.key not in (
          'report.all_branches.view',
          'customer.credit.update',
          'pos.return.override',
          'pos.discount.approve',
          'pos.return.approve'
        )
      )
    )
  on conflict (role_id, permission_id) do nothing;

  select id
  into target_role_id
  from public.roles
  where tenant_id = new.tenant_id
    and code = new.role
    and is_system
    and is_active
    and deleted_at is null;

  update public.user_role_assignments assignment
  set revoked_at = now()
  from public.roles assigned_role
  where assignment.user_id = new.id
    and assignment.tenant_id = new.tenant_id
    and assignment.revoked_at is null
    and assigned_role.id = assignment.role_id
    and assigned_role.is_system
    and assigned_role.code <> new.role;

  insert into public.user_role_assignments (tenant_id, user_id, role_id)
  values (new.tenant_id, new.id, target_role_id)
  on conflict (tenant_id, user_id, role_id)
    where revoked_at is null
  do nothing;

  return new;
end
$function$;

drop trigger if exists users_ensure_compatibility_role on public.users;
create trigger users_ensure_compatibility_role
after insert or update of tenant_id, role on public.users
for each row execute function public.ensure_compatibility_user_role();

revoke all on function public.ensure_compatibility_user_role()
from public, anon, authenticated;
