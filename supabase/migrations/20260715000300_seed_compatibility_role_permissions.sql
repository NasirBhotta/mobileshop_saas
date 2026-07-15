-- Roles Patch 4: mirror the current owner/manager/cashier behaviour in the
-- database-driven role foundation. Runtime authorization remains unchanged.

create or replace function public.sync_compatibility_role_permissions()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  -- These two current-runtime distinctions were not part of the initial
  -- catalog. Add them here without changing or enforcing application access.
  insert into public.permissions (
    key, module, action, name, description, is_active
  )
  values
    ('pos.return.approve', 'pos', 'approve',
     'Approve returns', 'Approve a sale return requiring authorization.', true),
    ('pos.return.override', 'pos', 'override',
     'Override return window', 'Override the configured sale return window.', true)
  on conflict (key) do update
  set module = excluded.module,
      action = excluded.action,
      name = excluded.name,
      description = excluded.description,
      is_active = excluded.is_active;

  -- Remove only assignments that contradict the current compatibility rules.
  -- Custom roles and every unrelated role-permission mapping remain untouched.
  delete from public.role_permissions rp
  using public.roles r, public.permissions p
  where rp.role_id = r.id
    and rp.permission_id = p.id
    and r.is_system
    and r.code in ('owner', 'manager', 'cashier')
    and (
      (r.code = 'manager' and p.key in (
        'report.all_branches.view',
        'customer.credit.update',
        'pos.return.override'
      ))
      or
      (r.code = 'cashier' and p.key in (
        'report.all_branches.view',
        'customer.credit.update',
        'pos.return.override',
        'pos.discount.approve',
        'pos.return.approve'
      ))
    );

  -- All active catalog permissions are currently unrestricted except for the
  -- explicitly preserved compatibility rules above.
  insert into public.role_permissions (role_id, permission_id)
  select r.id, p.id
  from public.roles r
  cross join public.permissions p
  where r.is_system
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
end
$function$;

revoke all on function public.sync_compatibility_role_permissions()
from public;
revoke all on function public.sync_compatibility_role_permissions()
from anon;
revoke all on function public.sync_compatibility_role_permissions()
from authenticated;

select public.sync_compatibility_role_permissions();
