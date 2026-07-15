-- Admin Portal Patch 2: secure tenant read and status management operations.

create or replace function public.require_active_platform_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null or not exists (
    select 1 from public.platform_admins pa
    where pa.user_id = caller_id
      and pa.admin_type = 'platform_admin'
      and pa.is_active
  ) then
    raise exception using
      errcode = '42501',
      message = 'Active platform administrator access is required.';
  end if;
  return caller_id;
end
$function$;

create or replace function public.platform_tenant_summary()
returns table (
  total_tenants bigint,
  active_tenants bigint,
  suspended_tenants bigint,
  starter_tenants bigint,
  business_tenants bigint,
  enterprise_tenants bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return query
  select
    count(*),
    count(*) filter (where lower(t.status) = 'active'),
    count(*) filter (where lower(t.status) = 'suspended'),
    count(*) filter (where lower(t.plan) = 'starter'),
    count(*) filter (where lower(t.plan) = 'business'),
    count(*) filter (where lower(t.plan) = 'enterprise')
  from public.tenants t;
end
$function$;

create or replace function public.platform_list_tenants(
  p_search text default null,
  p_status text default null,
  p_plan text default null
)
returns table (
  id uuid,
  shop_name text,
  business_type text,
  status text,
  plan text,
  branch_count integer,
  user_count bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return query
  select
    t.id, t.shop_name, t.business_type, t.status, t.plan,
    t.branch_count, count(u.id), t.created_at
  from public.tenants t
  left join public.users u on u.tenant_id = t.id
  where (nullif(trim(p_search), '') is null
         or t.shop_name ilike '%' || trim(p_search) || '%')
    and (nullif(trim(p_status), '') is null
         or lower(t.status) = lower(trim(p_status)))
    and (nullif(trim(p_plan), '') is null
         or lower(t.plan) = lower(trim(p_plan)))
  group by t.id
  order by t.created_at desc;
end
$function$;

create or replace function public.platform_get_tenant(p_tenant_id uuid)
returns table (
  id uuid,
  shop_name text,
  business_type text,
  status text,
  plan text,
  branch_count integer,
  user_count bigint,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return query
  select
    t.id, t.shop_name, t.business_type, t.status, t.plan,
    t.branch_count, count(u.id), t.created_at
  from public.tenants t
  left join public.users u on u.tenant_id = t.id
  where t.id = p_tenant_id
  group by t.id;
end
$function$;

create or replace function public.platform_set_tenant_status(
  p_tenant_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  caller_id uuid;
  old_status text;
  normalized_status text := lower(trim(p_status));
  audit_actor uuid;
begin
  caller_id := public.require_active_platform_admin();
  if normalized_status not in ('active', 'suspended') then
    raise exception using errcode = '22023', message = 'Tenant status must be active or suspended.';
  end if;

  select t.status into old_status
  from public.tenants t where t.id = p_tenant_id for update;
  if old_status is null then
    raise exception using errcode = 'P0002', message = 'Tenant not found.';
  end if;
  if lower(old_status) = normalized_status then return; end if;

  update public.tenants set status = normalized_status where id = p_tenant_id;
  select caller_id into audit_actor
  where exists (select 1 from public.users where id = caller_id);
  insert into public.entitlement_audit_logs (
    tenant_id, actor_user_id, action, entity_type, entity_id,
    reason, previous_value, new_value
  ) values (
    p_tenant_id, audit_actor, 'tenant.status_changed', 'tenant', p_tenant_id,
    nullif(trim(p_reason), ''), jsonb_build_object('status', old_status),
    jsonb_build_object('status', normalized_status)
  );
end
$function$;

revoke all on function public.require_active_platform_admin() from public, anon, authenticated;
revoke all on function public.platform_tenant_summary() from public, anon;
revoke all on function public.platform_list_tenants(text, text, text) from public, anon;
revoke all on function public.platform_get_tenant(uuid) from public, anon;
revoke all on function public.platform_set_tenant_status(uuid, text, text) from public, anon;

grant execute on function public.platform_tenant_summary() to authenticated, service_role;
grant execute on function public.platform_list_tenants(text, text, text) to authenticated, service_role;
grant execute on function public.platform_get_tenant(uuid) to authenticated, service_role;
grant execute on function public.platform_set_tenant_status(uuid, text, text) to authenticated, service_role;
