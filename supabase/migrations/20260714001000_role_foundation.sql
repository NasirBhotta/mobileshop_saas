-- Roles Patch 1: database-driven role foundation only.
-- Existing public.users.role and all current authorization paths are untouched.

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null check (length(trim(code)) > 0),
  name text not null check (length(trim(name)) > 0),
  description text,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint roles_deleted_inactive_check
    check (deleted_at is null or is_active = false),
  constraint roles_id_tenant_unique unique (id, tenant_id)
);

create unique index roles_tenant_code_unique
on public.roles (tenant_id, lower(code));

create index roles_tenant_active_idx
on public.roles (tenant_id, is_active)
where deleted_at is null;

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (length(trim(key)) > 0),
  module text not null check (length(trim(module)) > 0),
  action text not null check (length(trim(action)) > 0),
  description text,
  created_at timestamptz not null default now()
);

create index permissions_module_action_idx
on public.permissions (module, action);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete restrict,
  permission_id uuid not null references public.permissions(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create index role_permissions_permission_idx
on public.role_permissions (permission_id);

create table public.user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete restrict,
  role_id uuid not null,
  assigned_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint user_role_assignments_role_tenant_fkey
    foreign key (role_id, tenant_id)
    references public.roles(id, tenant_id)
    on delete restrict,
  constraint user_role_assignment_dates_check
    check (revoked_at is null or revoked_at >= assigned_at)
);

create unique index user_role_assignments_active_unique
on public.user_role_assignments (tenant_id, user_id, role_id)
where revoked_at is null;

create index user_role_assignments_user_idx
on public.user_role_assignments (tenant_id, user_id);

create index user_role_assignments_role_idx
on public.user_role_assignments (tenant_id, role_id);

create or replace function public.validate_user_role_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  user_tenant_id uuid;
  role_is_active boolean;
  role_deleted_at timestamptz;
begin
  select u.tenant_id
  into user_tenant_id
  from public.users u
  where u.id = new.user_id;

  if not found or user_tenant_id is distinct from new.tenant_id then
    raise exception using
      errcode = '23514',
      message = 'Role assignment user and role must belong to the same tenant.';
  end if;

  select r.is_active, r.deleted_at
  into role_is_active, role_deleted_at
  from public.roles r
  where r.id = new.role_id
    and r.tenant_id = new.tenant_id;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Role assignment user and role must belong to the same tenant.';
  end if;

  -- Existing assignments may be revoked after their role is deactivated or
  -- soft-deleted. Only a new assignment identity requires an active role.
  if tg_op = 'INSERT'
     or new.user_id is distinct from old.user_id
     or new.role_id is distinct from old.role_id
     or new.tenant_id is distinct from old.tenant_id then
    if not role_is_active or role_deleted_at is not null then
      raise exception using
        errcode = '23514',
        message = 'New assignments require an active, non-deleted role.';
    end if;
  end if;

  return new;
end
$function$;

revoke all on function public.validate_user_role_assignment() from public;
revoke all on function public.validate_user_role_assignment() from anon;
revoke all on function public.validate_user_role_assignment() from authenticated;

create trigger user_role_assignments_validate
before insert or update on public.user_role_assignments
for each row
execute function public.validate_user_role_assignment();

alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_role_assignments enable row level security;

create policy "tenant users can read roles"
on public.roles for select to authenticated
using (tenant_id = public.current_user_tenant_id());

create policy "owners can insert tenant roles"
on public.roles for insert to authenticated
with check (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'owner'
  )
);

create policy "owners can update tenant roles"
on public.roles for update to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'owner'
  )
)
with check (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'owner'
  )
);

create policy "authenticated users can read permissions"
on public.permissions for select to authenticated
using (true);

create policy "tenant users can read role permissions"
on public.role_permissions for select to authenticated
using (
  exists (
    select 1 from public.roles r
    where r.id = role_permissions.role_id
      and r.tenant_id = public.current_user_tenant_id()
  )
);

create policy "owners can insert role permissions"
on public.role_permissions for insert to authenticated
with check (
  exists (
    select 1 from public.roles r
    where r.id = role_permissions.role_id
      and r.tenant_id = public.current_user_tenant_id()
  )
  and exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'owner'
  )
);

create policy "owners can delete role permissions"
on public.role_permissions for delete to authenticated
using (
  exists (
    select 1 from public.roles r
    where r.id = role_permissions.role_id
      and r.tenant_id = public.current_user_tenant_id()
  )
  and exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'owner'
  )
);

create policy "tenant users can read role assignments"
on public.user_role_assignments for select to authenticated
using (tenant_id = public.current_user_tenant_id());

create policy "owners can insert role assignments"
on public.user_role_assignments for insert to authenticated
with check (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'owner'
  )
);

create policy "owners can update role assignments"
on public.user_role_assignments for update to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'owner'
  )
)
with check (
  tenant_id = public.current_user_tenant_id()
  and exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'owner'
  )
);

revoke all on table public.roles from anon;
revoke all on table public.permissions from anon;
revoke all on table public.role_permissions from anon;
revoke all on table public.user_role_assignments from anon;

revoke all on table public.roles from authenticated;
grant select, insert, update on table public.roles to authenticated;

revoke all on table public.permissions from authenticated;
grant select on table public.permissions to authenticated;

revoke all on table public.role_permissions from authenticated;
grant select, insert, delete on table public.role_permissions to authenticated;

revoke all on table public.user_role_assignments from authenticated;
grant select, insert, update on table public.user_role_assignments to authenticated;
