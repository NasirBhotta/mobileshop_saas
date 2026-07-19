-- Do not let RLS visibility be mistaken for physical tenant deletion.

create or replace function public.block_direct_tenant_detach()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
begin
  if old.tenant_id is not null
     and new.tenant_id is null
     and current_user not in ('postgres', 'supabase_admin', 'service_role') then
    raise exception using
      errcode = '42501',
      message = 'Tenant association can only be cleared through validated recovery.';
  end if;
  
  return new;
end
$function$;

drop trigger if exists users_00_block_direct_tenant_detach on public.users;
create trigger users_00_block_direct_tenant_detach
before update of tenant_id on public.users
for each row
execute function public.block_direct_tenant_detach();

create or replace function public.clear_stale_tenant_link()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  linked_tenant_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select u.tenant_id
  into linked_tenant_id
  from public.users u
  where u.id = auth.uid()
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'User profile not found.';
  end if;

  if linked_tenant_id is null then
    return true;
  end if;

  if exists (
    select 1 from public.tenants t where t.id = linked_tenant_id
  ) then
    return false;
  end if;

  update public.users
  set tenant_id = null,
      branch_id = null
  where id = auth.uid();

  return true;
end
$function$;

revoke all on function public.block_direct_tenant_detach() from public, anon, authenticated;
revoke all on function public.clear_stale_tenant_link() from public, anon;
grant execute on function public.clear_stale_tenant_link() to authenticated, service_role;

