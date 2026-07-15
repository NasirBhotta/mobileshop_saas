-- Admin Portal Patch 3: active platform-admin package management facade.

alter table public.plans
add column monthly_price numeric(12, 2)
check (monthly_price is null or monthly_price >= 0);

create or replace function public.platform_admin_list_plans()
returns table (
  id uuid, key text, name text, description text, monthly_price numeric,
  is_active boolean, affected_tenant_count bigint, created_at timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return query
  select p.id, p.key, p.name, p.description, p.monthly_price, p.is_active,
    count(s.id) filter (where s.is_active and s.deleted_at is null), p.created_at
  from public.plans p
  left join public.tenant_subscriptions s on s.plan_id = p.id
  group by p.id
  order by p.created_at;
end
$function$;

create or replace function public.platform_admin_get_plan(p_plan_id uuid)
returns table (
  id uuid, key text, name text, description text, monthly_price numeric,
  is_active boolean, affected_tenant_count bigint, created_at timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return query
  select p.id, p.key, p.name, p.description, p.monthly_price, p.is_active,
    count(s.id) filter (where s.is_active and s.deleted_at is null), p.created_at
  from public.plans p
  left join public.tenant_subscriptions s on s.plan_id = p.id
  where p.id = p_plan_id
  group by p.id;
end
$function$;

create or replace function public.platform_admin_list_plan_features(p_plan_id uuid)
returns table (
  feature_id uuid, feature_key text, module text, name text,
  description text, enabled boolean
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  if not exists (select 1 from public.plans where id = p_plan_id) then
    raise exception using errcode = 'P0002', message = 'Plan not found.';
  end if;
  return query
  select f.id, f.key, f.module, f.name, f.description,
    coalesce(pf.enabled and pf.is_active and pf.deleted_at is null, false)
  from public.features f
  left join public.plan_features pf
    on pf.feature_id = f.id and pf.plan_id = p_plan_id
  where f.is_active and f.deleted_at is null
  order by f.module, f.name;
end
$function$;

create or replace function public.platform_admin_list_plan_limits(p_plan_id uuid)
returns table (id uuid, key text, value numeric, reason text)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return query
  select l.id, l.key, l.value, l.reason
  from public.plan_limits l
  where l.plan_id = p_plan_id and l.is_active and l.deleted_at is null
  order by l.key;
end
$function$;

create or replace function public.platform_admin_upsert_plan(
  p_plan_id uuid, p_key text, p_name text, p_description text,
  p_monthly_price numeric
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare result_id uuid;
begin
  perform public.require_active_platform_admin();
  if p_monthly_price is not null and p_monthly_price < 0 then
    raise exception using errcode = '22023', message = 'Monthly price cannot be negative.';
  end if;
  result_id := public.platform_upsert_plan(p_plan_id, p_key, p_name, p_description);
  update public.plans set monthly_price = p_monthly_price where id = result_id;
  return result_id;
end
$function$;

create or replace function public.platform_admin_set_plan_active(
  p_plan_id uuid, p_is_active boolean
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  perform public.platform_set_plan_active(p_plan_id, p_is_active);
end
$function$;

create or replace function public.platform_admin_set_plan_feature(
  p_plan_id uuid, p_feature_id uuid, p_enabled boolean, p_reason text default null
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return public.platform_set_plan_feature(p_plan_id, p_feature_id, p_enabled, p_reason);
end
$function$;

create or replace function public.platform_admin_set_plan_limit(
  p_plan_id uuid, p_key text, p_value numeric, p_reason text default null
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return public.platform_set_plan_limit(p_plan_id, p_key, p_value, p_reason);
end
$function$;

do $grants$
declare signature text;
begin
  foreach signature in array array[
    'public.platform_admin_list_plans()',
    'public.platform_admin_get_plan(uuid)',
    'public.platform_admin_list_plan_features(uuid)',
    'public.platform_admin_list_plan_limits(uuid)',
    'public.platform_admin_upsert_plan(uuid,text,text,text,numeric)',
    'public.platform_admin_set_plan_active(uuid,boolean)',
    'public.platform_admin_set_plan_feature(uuid,uuid,boolean,text)',
    'public.platform_admin_set_plan_limit(uuid,text,numeric,text)'
  ] loop
    execute format('revoke all on function %s from public', signature);
    execute format('revoke all on function %s from anon', signature);
    execute format('grant execute on function %s to authenticated', signature);
    execute format('grant execute on function %s to service_role', signature);
  end loop;
end
$grants$;
