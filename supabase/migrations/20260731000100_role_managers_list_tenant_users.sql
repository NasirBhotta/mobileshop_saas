-- Role managers need a tenant-scoped staff directory for assigning roles.
-- public.users remains self-readable only; this function exposes only the
-- profile fields required by the role-management screen.

create or replace function public.list_role_management_users()
returns table (
  id uuid,
  full_name text,
  email text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
begin
  return query
  select u.id, u.full_name, u.email
  from public.users u
  where u.tenant_id = actor_tenant_id
    and u.is_active = true
    and u.deleted_at is null
  order by u.full_name nulls last, u.email;
end
$function$;

revoke all on function public.list_role_management_users() from public;
revoke all on function public.list_role_management_users() from anon;
grant execute on function public.list_role_management_users()
to authenticated;
