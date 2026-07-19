-- Complete onboarding only through a server-validated operation.

create or replace function public.protect_tenant_setup_complete()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
begin
  if new.setup_complete is not distinct from old.setup_complete then
    return new;
  end if;

  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  raise exception using
    errcode = '42501',
    message = 'Tenant setup can only be completed through the validated setup operation.';
end
$function$;

drop trigger if exists tenants_protect_setup_complete on public.tenants;
create trigger tenants_protect_setup_complete
before update of setup_complete on public.tenants
for each row
execute function public.protect_tenant_setup_complete();

create or replace function public.complete_tenant_setup(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  required_branch_count integer;
  active_branch_count integer;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = p_tenant_id
      and u.role = 'owner'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Only the tenant owner can complete setup.';
  end if;

  select greatest(t.branch_count, 1)
  into required_branch_count
  from public.tenants t
  where t.id = p_tenant_id
  for update;

  if required_branch_count is null then
    raise exception using errcode = 'P0002', message = 'Tenant not found.';
  end if;

  select count(*)::integer
  into active_branch_count
  from public.branches b
  where b.tenant_id = p_tenant_id
    and b.is_active = true;

  if active_branch_count < required_branch_count then
    raise exception using
      errcode = '23514',
      message = 'Required active branches must be created before completing setup.';
  end if;

  update public.tenants
  set setup_complete = true
  where id = p_tenant_id;
end
$function$;

revoke all on function public.protect_tenant_setup_complete() from public, anon, authenticated;
revoke all on function public.complete_tenant_setup(uuid) from public, anon;
grant execute on function public.complete_tenant_setup(uuid) to authenticated, service_role;
