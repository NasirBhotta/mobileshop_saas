-- Additive branch-scoped authorization foundation.
-- Existing users.role, user_role_assignments, permission evaluation, module
-- authorization, and entitlement behavior remain unchanged in this phase.

create table public.user_branch_role_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null,
  branch_id uuid not null,
  role_id uuid not null,
  assigned_by uuid not null references auth.users(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint user_branch_roles_user_tenant_fkey
    foreign key (user_id, tenant_id)
    references public.users(id, tenant_id)
    on delete restrict,
  constraint user_branch_roles_branch_tenant_fkey
    foreign key (branch_id, tenant_id)
    references public.branches(id, tenant_id)
    on delete restrict,
  constraint user_branch_roles_role_tenant_fkey
    foreign key (role_id, tenant_id)
    references public.roles(id, tenant_id)
    on delete restrict,
  constraint user_branch_roles_dates_check
    check (revoked_at is null or revoked_at >= assigned_at)
);

create unique index user_branch_roles_active_unique
on public.user_branch_role_assignments (tenant_id, user_id, branch_id)
where revoked_at is null;

create index user_branch_roles_user_lookup_idx
on public.user_branch_role_assignments (tenant_id, user_id, branch_id);

create index user_branch_roles_branch_lookup_idx
on public.user_branch_role_assignments (tenant_id, branch_id)
where revoked_at is null;

create table public.user_branch_permission_overrides (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null,
  branch_id uuid not null,
  permission_id uuid not null references public.permissions(id)
    on delete restrict,
  is_allowed boolean not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, user_id, branch_id, permission_id),
  constraint user_branch_overrides_user_tenant_fkey
    foreign key (user_id, tenant_id)
    references public.users(id, tenant_id)
    on delete restrict,
  constraint user_branch_overrides_branch_tenant_fkey
    foreign key (branch_id, tenant_id)
    references public.branches(id, tenant_id)
    on delete restrict
);

create index user_branch_overrides_user_lookup_idx
on public.user_branch_permission_overrides (tenant_id, user_id, branch_id);

alter table public.user_branch_role_assignments enable row level security;
alter table public.user_branch_permission_overrides enable row level security;

create or replace function public.require_tenant_owner()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid;
begin
  select u.tenant_id
  into actor_tenant_id
  from public.users u
  where u.id = auth.uid()
    and u.role = 'owner'
    and u.is_active
    and u.deleted_at is null;

  if actor_tenant_id is null then
    raise exception using
      errcode = '42501',
      message = 'Tenant owner access is required.';
  end if;

  return actor_tenant_id;
end
$function$;

create policy "users read own branch role assignments"
on public.user_branch_role_assignments
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and (
    user_id = auth.uid()
    or exists (
      select 1
      from public.users actor
      where actor.id = auth.uid()
        and actor.tenant_id = user_branch_role_assignments.tenant_id
        and actor.role = 'owner'
        and actor.is_active
        and actor.deleted_at is null
    )
  )
);

create policy "users read own branch permission overrides"
on public.user_branch_permission_overrides
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and (
    user_id = auth.uid()
    or exists (
      select 1
      from public.users actor
      where actor.id = auth.uid()
        and actor.tenant_id = user_branch_permission_overrides.tenant_id
        and actor.role = 'owner'
        and actor.is_active
        and actor.deleted_at is null
    )
  )
);

create or replace function public.set_user_branch_role(
  p_user_id uuid,
  p_branch_id uuid,
  p_role_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_tenant_owner();
begin
  if not exists (
    select 1
    from public.users target_user
    where target_user.id = p_user_id
      and target_user.tenant_id = actor_tenant_id
      and target_user.role <> 'owner'
      and target_user.is_active
      and target_user.deleted_at is null
  ) then
    raise exception using
      errcode = '42501',
      message = 'An active staff user in the current tenant is required.';
  end if;

  if not exists (
    select 1
    from public.branches branch
    where branch.id = p_branch_id
      and branch.tenant_id = actor_tenant_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Branch is outside the current tenant.';
  end if;

  if p_role_id is not null and not exists (
    select 1
    from public.roles role
    where role.id = p_role_id
      and role.tenant_id = actor_tenant_id
      and role.is_active
      and role.deleted_at is null
      and not (role.is_system and role.code = 'owner')
  ) then
    raise exception using
      errcode = '42501',
      message = 'An active non-owner role in the current tenant is required.';
  end if;

  update public.user_branch_role_assignments
  set revoked_at = now()
  where tenant_id = actor_tenant_id
    and user_id = p_user_id
    and branch_id = p_branch_id
    and revoked_at is null
    and (p_role_id is null or role_id <> p_role_id);

  if p_role_id is not null and not exists (
    select 1
    from public.user_branch_role_assignments assignment
    where assignment.tenant_id = actor_tenant_id
      and assignment.user_id = p_user_id
      and assignment.branch_id = p_branch_id
      and assignment.role_id = p_role_id
      and assignment.revoked_at is null
  ) then
    insert into public.user_branch_role_assignments (
      tenant_id,
      user_id,
      branch_id,
      role_id,
      assigned_by
    ) values (
      actor_tenant_id,
      p_user_id,
      p_branch_id,
      p_role_id,
      auth.uid()
    );
  end if;
end
$function$;

create or replace function public.set_user_branch_permission_override(
  p_user_id uuid,
  p_branch_id uuid,
  p_permission_key text,
  p_is_allowed boolean default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_tenant_owner();
  target_permission_id uuid;
begin
  if not exists (
    select 1
    from public.users target_user
    where target_user.id = p_user_id
      and target_user.tenant_id = actor_tenant_id
      and target_user.role <> 'owner'
      and target_user.is_active
      and target_user.deleted_at is null
  ) then
    raise exception using
      errcode = '42501',
      message = 'An active staff user in the current tenant is required.';
  end if;

  if not exists (
    select 1
    from public.branches branch
    where branch.id = p_branch_id
      and branch.tenant_id = actor_tenant_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Branch is outside the current tenant.';
  end if;

  select permission.id
  into target_permission_id
  from public.permissions permission
  where permission.key = trim(p_permission_key)
    and permission.is_active;

  if target_permission_id is null then
    raise exception using
      errcode = '22023',
      message = 'An active permission key is required.';
  end if;

  if p_is_allowed is null then
    delete from public.user_branch_permission_overrides
    where tenant_id = actor_tenant_id
      and user_id = p_user_id
      and branch_id = p_branch_id
      and permission_id = target_permission_id;
    return;
  end if;

  insert into public.user_branch_permission_overrides (
    tenant_id,
    user_id,
    branch_id,
    permission_id,
    is_allowed,
    created_by
  ) values (
    actor_tenant_id,
    p_user_id,
    p_branch_id,
    target_permission_id,
    p_is_allowed,
    auth.uid()
  )
  on conflict (tenant_id, user_id, branch_id, permission_id)
  do update
  set is_allowed = excluded.is_allowed,
      created_by = excluded.created_by,
      updated_at = now();
end
$function$;

revoke all on table public.user_branch_role_assignments
from public, anon, authenticated;
revoke all on table public.user_branch_permission_overrides
from public, anon, authenticated;

grant select on table public.user_branch_role_assignments to authenticated;
grant select on table public.user_branch_permission_overrides to authenticated;

revoke all on function public.require_tenant_owner()
from public, anon, authenticated;
revoke all on function public.set_user_branch_role(uuid, uuid, uuid)
from public, anon;
revoke all on function public.set_user_branch_permission_override(
  uuid, uuid, text, boolean
) from public, anon;

grant execute on function public.set_user_branch_role(uuid, uuid, uuid)
to authenticated;
grant execute on function public.set_user_branch_permission_override(
  uuid, uuid, text, boolean
) to authenticated;
