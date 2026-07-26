-- Harden and atomically manage branch permission overrides. Authorization
-- remains in shadow mode; this migration does not change module decisions.

create or replace function public.validate_user_branch_permission_override()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if not exists (
    select 1
    from public.user_branch_role_assignments assignment
    where assignment.tenant_id = new.tenant_id
      and assignment.user_id = new.user_id
      and assignment.branch_id = new.branch_id
      and assignment.revoked_at is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'An active branch role is required before permission overrides.';
  end if;
  return new;
end
$function$;

create trigger user_branch_permission_overrides_validate
before insert or update on public.user_branch_permission_overrides
for each row execute function public.validate_user_branch_permission_override();

create or replace function public.cleanup_revoked_branch_role_overrides()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if old.revoked_at is null and new.revoked_at is not null then
    delete from public.user_branch_permission_overrides override_row
    where override_row.tenant_id = new.tenant_id
      and override_row.user_id = new.user_id
      and override_row.branch_id = new.branch_id;
  end if;
  return new;
end
$function$;

create trigger user_branch_role_override_cleanup
after update of revoked_at on public.user_branch_role_assignments
for each row execute function public.cleanup_revoked_branch_role_overrides();

create or replace function public.replace_user_branch_permission_overrides(
  p_user_id uuid,
  p_branch_id uuid,
  p_overrides jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_tenant_owner();
  requested_count integer;
  valid_count integer;
begin
  if p_overrides is null or jsonb_typeof(p_overrides) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'Permission overrides must be a JSON object.';
  end if;

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
    from public.user_branch_role_assignments assignment
    where assignment.tenant_id = actor_tenant_id
      and assignment.user_id = p_user_id
      and assignment.branch_id = p_branch_id
      and assignment.revoked_at is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'An active branch role is required before permission overrides.';
  end if;

  if exists (
    select 1
    from jsonb_each(p_overrides) entry
    where jsonb_typeof(entry.value) <> 'boolean'
  ) then
    raise exception using
      errcode = '22023',
      message = 'Every permission override must be true or false.';
  end if;

  select count(*), count(permission.id)
  into requested_count, valid_count
  from jsonb_each(p_overrides) entry
  left join public.permissions permission
    on permission.key = entry.key
   and permission.is_active;

  if requested_count <> valid_count then
    raise exception using
      errcode = '22023',
      message = 'Every override must reference an active permission.';
  end if;

  delete from public.user_branch_permission_overrides
  where tenant_id = actor_tenant_id
    and user_id = p_user_id
    and branch_id = p_branch_id;

  insert into public.user_branch_permission_overrides (
    tenant_id, user_id, branch_id, permission_id, is_allowed, created_by
  )
  select
    actor_tenant_id,
    p_user_id,
    p_branch_id,
    permission.id,
    (entry.value #>> '{}')::boolean,
    auth.uid()
  from jsonb_each(p_overrides) entry
  join public.permissions permission
    on permission.key = entry.key
   and permission.is_active;
end
$function$;

revoke all on function public.validate_user_branch_permission_override()
from public, anon, authenticated;
revoke all on function public.cleanup_revoked_branch_role_overrides()
from public, anon, authenticated;
revoke all on function public.replace_user_branch_permission_overrides(
  uuid, uuid, jsonb
) from public, anon;
grant execute on function public.replace_user_branch_permission_overrides(
  uuid, uuid, jsonb
) to authenticated;
