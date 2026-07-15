-- Roles Patch 7: tenant-safe backend role management operations.
-- Legacy public.users.role and all existing feature/package behaviour remain unchanged.

create table public.role_management_audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  actor_user_id uuid not null references public.users(id) on delete restrict,
  action text not null check (length(trim(action)) > 0),
  role_id uuid references public.roles(id) on delete restrict,
  target_user_id uuid references public.users(id) on delete restrict,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index role_management_audit_tenant_created_idx
on public.role_management_audit_log (tenant_id, created_at desc);

alter table public.role_management_audit_log enable row level security;

revoke all on table public.role_management_audit_log from anon;
revoke all on table public.role_management_audit_log from authenticated;
grant select on table public.role_management_audit_log to authenticated;

create or replace function public.current_user_has_permission(
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select exists (
    select 1
    from public.users u
    join public.user_role_assignments ura
      on ura.user_id = u.id
     and ura.tenant_id = u.tenant_id
     and ura.revoked_at is null
    join public.roles r
      on r.id = ura.role_id
     and r.tenant_id = ura.tenant_id
     and r.is_active
     and r.deleted_at is null
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p
      on p.id = rp.permission_id
     and p.is_active
    where u.id = auth.uid()
      and u.tenant_id is not null
      and p.key = p_permission_key
  );
$function$;

revoke all on function public.current_user_has_permission(text) from public;
revoke all on function public.current_user_has_permission(text) from anon;
grant execute on function public.current_user_has_permission(text)
to authenticated;

create policy "role managers can read role audit log"
on public.role_management_audit_log
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and public.current_user_has_permission('user.role.manage')
);

create or replace function public.require_role_manager_tenant()
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
  where u.id = auth.uid();

  if actor_tenant_id is null
     or not public.current_user_has_permission('user.role.manage') then
    raise exception using
      errcode = '42501',
      message = 'Role management permission is required.';
  end if;

  return actor_tenant_id;
end
$function$;

revoke all on function public.require_role_manager_tenant() from public;
revoke all on function public.require_role_manager_tenant() from anon;
revoke all on function public.require_role_manager_tenant() from authenticated;

create or replace function public.create_custom_role(
  p_code text,
  p_name text,
  p_description text default null,
  p_permission_keys text[] default array[]::text[]
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
  new_role_id uuid;
  requested_count integer;
  valid_count integer;
begin
  p_code := lower(trim(p_code));
  p_name := trim(p_name);
  if p_code !~ '^[a-z][a-z0-9_]{1,49}$' then
    raise exception using errcode = '22023', message = 'Invalid role code.';
  end if;
  if p_name is null or length(p_name) = 0 then
    raise exception using errcode = '22023', message = 'Role name is required.';
  end if;

  select count(distinct requested.permission_key), count(distinct p.key)
  into requested_count, valid_count
  from unnest(coalesce(p_permission_keys, array[]::text[]))
    as requested(permission_key)
  left join public.permissions p
    on p.key = requested.permission_key and p.is_active;
  if requested_count <> valid_count then
    raise exception using
      errcode = '22023',
      message = 'Every role permission must reference an active permission.';
  end if;

  insert into public.roles (
    tenant_id, code, name, description, is_system, is_active, deleted_at
  ) values (
    actor_tenant_id, p_code, p_name, p_description, false, true, null
  )
  returning id into new_role_id;

  insert into public.role_permissions (role_id, permission_id)
  select new_role_id, p.id
  from public.permissions p
  where p.is_active and p.key = any(coalesce(p_permission_keys, array[]::text[]))
  on conflict do nothing;

  insert into public.role_management_audit_log (
    tenant_id, actor_user_id, action, role_id, details
  ) values (
    actor_tenant_id, auth.uid(), 'role.created', new_role_id,
    jsonb_build_object('code', p_code, 'name', p_name,
      'permission_keys', coalesce(p_permission_keys, array[]::text[]))
  );
  return new_role_id;
end
$function$;

create or replace function public.rename_role(
  p_role_id uuid,
  p_name text,
  p_description text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
begin
  p_name := trim(p_name);
  if p_name is null or length(p_name) = 0 then
    raise exception using errcode = '22023', message = 'Role name is required.';
  end if;

  update public.roles
  set name = p_name, description = p_description
  where id = p_role_id and tenant_id = actor_tenant_id;
  if not found then
    raise exception using errcode = '42501', message = 'Role is outside the current tenant.';
  end if;

  insert into public.role_management_audit_log (
    tenant_id, actor_user_id, action, role_id, details
  ) values (
    actor_tenant_id, auth.uid(), 'role.renamed', p_role_id,
    jsonb_build_object('name', p_name, 'description', p_description)
  );
end
$function$;

create or replace function public.update_role_permissions(
  p_role_id uuid,
  p_permission_keys text[]
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
  target_role public.roles%rowtype;
  requested_count integer;
  valid_count integer;
begin
  select * into target_role from public.roles
  where id = p_role_id and tenant_id = actor_tenant_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Role is outside the current tenant.';
  end if;

  select count(distinct requested.permission_key), count(distinct p.key)
  into requested_count, valid_count
  from unnest(coalesce(p_permission_keys, array[]::text[]))
    as requested(permission_key)
  left join public.permissions p
    on p.key = requested.permission_key and p.is_active;
  if requested_count <> valid_count then
    raise exception using
      errcode = '22023',
      message = 'Every role permission must reference an active permission.';
  end if;
  if target_role.is_system and target_role.code = 'owner'
     and not ('user.role.manage' = any(coalesce(p_permission_keys, array[]::text[]))) then
    raise exception using
      errcode = '23514',
      message = 'Owner role must retain role-management permission.';
  end if;

  delete from public.role_permissions where role_id = p_role_id;
  insert into public.role_permissions (role_id, permission_id)
  select p_role_id, p.id from public.permissions p
  where p.is_active and p.key = any(coalesce(p_permission_keys, array[]::text[]))
  on conflict do nothing;

  insert into public.role_management_audit_log (
    tenant_id, actor_user_id, action, role_id, details
  ) values (
    actor_tenant_id, auth.uid(), 'role.permissions_updated', p_role_id,
    jsonb_build_object('permission_keys', coalesce(p_permission_keys, array[]::text[]))
  );
end
$function$;

create or replace function public.assign_user_to_role(
  p_user_id uuid,
  p_role_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
  target_role public.roles%rowtype;
  active_owner_count integer;
  user_is_owner boolean;
  owner_role_id uuid;
begin
  if not exists (
    select 1 from public.users u
    where u.id = p_user_id and u.tenant_id = actor_tenant_id
  ) then
    raise exception using errcode = '42501', message = 'User is outside the current tenant.';
  end if;

  select * into target_role from public.roles
  where id = p_role_id and tenant_id = actor_tenant_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'Role is outside the current tenant.';
  end if;
  if not target_role.is_active or target_role.deleted_at is not null then
    raise exception using errcode = '23514', message = 'Inactive roles cannot be assigned.';
  end if;

  select exists (
    select 1 from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.tenant_id = actor_tenant_id
      and ura.user_id = p_user_id
      and ura.revoked_at is null
      and r.is_system and r.code = 'owner' and r.is_active
  ) into user_is_owner;

  if user_is_owner and not (target_role.is_system and target_role.code = 'owner') then
    select r.id into owner_role_id
    from public.roles r
    where r.tenant_id = actor_tenant_id
      and r.is_system and r.code = 'owner'
    for update;
    select count(distinct ura.user_id) into active_owner_count
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.tenant_id = actor_tenant_id
      and ura.revoked_at is null
      and r.is_system and r.code = 'owner' and r.is_active;
    if active_owner_count <= 1 then
      raise exception using
        errcode = '23514',
        message = 'The last active owner cannot be reassigned.';
    end if;
  end if;

  update public.user_role_assignments
  set revoked_at = now()
  where tenant_id = actor_tenant_id
    and user_id = p_user_id
    and role_id <> p_role_id
    and revoked_at is null;

  insert into public.user_role_assignments (tenant_id, user_id, role_id)
  values (actor_tenant_id, p_user_id, p_role_id)
  on conflict (tenant_id, user_id, role_id) where revoked_at is null do nothing;

  insert into public.role_management_audit_log (
    tenant_id, actor_user_id, action, role_id, target_user_id
  ) values (
    actor_tenant_id, auth.uid(), 'user.role_assigned', p_role_id, p_user_id
  );
end
$function$;

create or replace function public.move_role_users(
  p_from_role_id uuid,
  p_to_role_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
  source_role public.roles%rowtype;
  target_role public.roles%rowtype;
  moved_count integer;
  moved_user_ids uuid[];
begin
  if p_from_role_id = p_to_role_id then
    raise exception using errcode = '22023', message = 'Source and target roles must differ.';
  end if;
  select * into source_role from public.roles
  where id = p_from_role_id and tenant_id = actor_tenant_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'Source role is outside the current tenant.';
  end if;
  select * into target_role from public.roles
  where id = p_to_role_id and tenant_id = actor_tenant_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'Target role is outside the current tenant.';
  end if;
  if not target_role.is_active or target_role.deleted_at is not null then
    raise exception using errcode = '23514', message = 'Inactive roles cannot be assigned.';
  end if;
  if source_role.is_system and source_role.code = 'owner' then
    raise exception using errcode = '23514', message = 'Owner assignments cannot be moved in bulk.';
  end if;

  select coalesce(array_agg(ura.user_id), array[]::uuid[])
  into moved_user_ids
  from public.user_role_assignments ura
  where ura.tenant_id = actor_tenant_id
    and ura.role_id = p_from_role_id and ura.revoked_at is null;
  moved_count := cardinality(moved_user_ids);

  insert into public.user_role_assignments (tenant_id, user_id, role_id)
  select actor_tenant_id, moved_user_id, p_to_role_id
  from unnest(moved_user_ids) moved_user_id
  on conflict (tenant_id, user_id, role_id) where revoked_at is null do nothing;

  update public.user_role_assignments ura
  set revoked_at = now()
  where ura.tenant_id = actor_tenant_id
    and ura.role_id = p_from_role_id
    and ura.revoked_at is null;

  insert into public.role_management_audit_log (
    tenant_id, actor_user_id, action, role_id, details
  ) values (
    actor_tenant_id, auth.uid(), 'role.users_moved', p_from_role_id,
    jsonb_build_object('to_role_id', p_to_role_id, 'moved_count', moved_count)
  );
  return moved_count;
end
$function$;

create or replace function public.set_role_active(
  p_role_id uuid,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
  target_role public.roles%rowtype;
begin
  select * into target_role from public.roles
  where id = p_role_id and tenant_id = actor_tenant_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'Role is outside the current tenant.';
  end if;
  if target_role.is_system and target_role.code = 'owner' and not p_is_active then
    raise exception using errcode = '23514', message = 'Owner system role cannot be deactivated.';
  end if;
  if not p_is_active and exists (
    select 1 from public.user_role_assignments ura
    where ura.tenant_id = actor_tenant_id
      and ura.role_id = p_role_id and ura.revoked_at is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'Move assigned users before deactivating this role.';
  end if;

  update public.roles
  set is_active = p_is_active,
      deleted_at = case when p_is_active then null else deleted_at end
  where id = p_role_id;

  insert into public.role_management_audit_log (
    tenant_id, actor_user_id, action, role_id, details
  ) values (
    actor_tenant_id, auth.uid(),
    case when p_is_active then 'role.reactivated' else 'role.deactivated' end,
    p_role_id, jsonb_build_object('is_active', p_is_active)
  );
end
$function$;

revoke all on function public.create_custom_role(text, text, text, text[]) from public, anon;
revoke all on function public.rename_role(uuid, text, text) from public, anon;
revoke all on function public.update_role_permissions(uuid, text[]) from public, anon;
revoke all on function public.assign_user_to_role(uuid, uuid) from public, anon;
revoke all on function public.move_role_users(uuid, uuid) from public, anon;
revoke all on function public.set_role_active(uuid, boolean) from public, anon;

grant execute on function public.create_custom_role(text, text, text, text[]) to authenticated;
grant execute on function public.rename_role(uuid, text, text) to authenticated;
grant execute on function public.update_role_permissions(uuid, text[]) to authenticated;
grant execute on function public.assign_user_to_role(uuid, uuid) to authenticated;
grant execute on function public.move_role_users(uuid, uuid) to authenticated;
grant execute on function public.set_role_active(uuid, boolean) to authenticated;
