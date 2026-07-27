-- Database-side equivalent of BranchPermissionShadowEvaluator.
-- It preserves legacy access only for users with no branch-role configuration.

create or replace function public.current_user_has_branch_permission(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_permission_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor public.users%rowtype;
  v_permission_id uuid;
  v_role_id uuid;
  v_override boolean;
begin
  select u.*
  into v_actor
  from public.users u
  where u.id = auth.uid();

  if v_actor.id is null
     or v_actor.tenant_id <> p_tenant_id
     or not v_actor.is_active
     or v_actor.deleted_at is not null then
    return false;
  end if;

  if not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.tenant_id = p_tenant_id
  ) then
    return false;
  end if;

  if v_actor.role = 'owner' then
    return true;
  end if;

  select p.id
  into v_permission_id
  from public.permissions p
  where p.key = p_permission_key
    and p.is_active;

  if v_permission_id is null then
    return false;
  end if;

  -- Historical assignments intentionally count as configuration. Revoking a
  -- final branch role must not silently restore tenant-wide legacy access.
  if not exists (
    select 1
    from public.user_branch_role_assignments assignment
    where assignment.tenant_id = p_tenant_id
      and assignment.user_id = auth.uid()
  ) then
    return public.current_user_has_permission(p_permission_key);
  end if;

  select assignment.role_id
  into v_role_id
  from public.user_branch_role_assignments assignment
  join public.roles role
    on role.id = assignment.role_id
   and role.tenant_id = assignment.tenant_id
   and role.is_active
   and role.deleted_at is null
  where assignment.tenant_id = p_tenant_id
    and assignment.user_id = auth.uid()
    and assignment.branch_id = p_branch_id
    and assignment.revoked_at is null
  limit 1;

  if v_role_id is null then
    return false;
  end if;

  select override.is_allowed
  into v_override
  from public.user_branch_permission_overrides override
  where override.tenant_id = p_tenant_id
    and override.user_id = auth.uid()
    and override.branch_id = p_branch_id
    and override.permission_id = v_permission_id;

  if found then
    return v_override;
  end if;

  return exists (
    select 1
    from public.role_permissions role_permission
    where role_permission.role_id = v_role_id
      and role_permission.permission_id = v_permission_id
  );
end;
$$;

revoke all on function public.current_user_has_branch_permission(
  uuid, uuid, text
) from public, anon;

grant execute on function public.current_user_has_branch_permission(
  uuid, uuid, text
) to authenticated;
