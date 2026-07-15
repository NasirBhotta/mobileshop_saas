-- Admin Portal Patch 4: tenant subscription and override administration.

create or replace function public.platform_admin_get_tenant_subscription(
  p_tenant_id uuid
)
returns table (
  subscription_id uuid,
  plan_id uuid,
  plan_key text,
  plan_name text,
  subscription_status text,
  starts_at timestamptz,
  expires_at timestamptz,
  reason text
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  if not exists (select 1 from public.tenants where id = p_tenant_id) then
    raise exception using errcode = 'P0002', message = 'Tenant not found.';
  end if;
  return query
  select s.id, p.id, p.key, p.name, s.status, s.starts_at, s.expires_at, s.reason
  from public.tenant_subscriptions s
  join public.plans p on p.id = s.plan_id
  where s.tenant_id = p_tenant_id and s.is_active and s.deleted_at is null
  order by s.created_at desc
  limit 1;
end
$function$;

create or replace function public.platform_admin_get_tenant_features(
  p_tenant_id uuid
)
returns table (
  feature_id uuid,
  feature_key text,
  module text,
  feature_name text,
  plan_enabled boolean,
  override_enabled boolean,
  override_reason text,
  override_starts_at timestamptz,
  override_expires_at timestamptz,
  override_is_effective boolean,
  effective_enabled boolean
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return query
  with subscription as (
    select s.plan_id
    from public.tenant_subscriptions s
    where s.tenant_id = p_tenant_id and s.is_active and s.deleted_at is null
    order by s.created_at desc limit 1
  )
  select
    f.id, f.key, f.module, f.name,
    coalesce(
      pf.enabled and pf.is_active and pf.deleted_at is null
      and (pf.starts_at is null or pf.starts_at <= now())
      and (pf.expires_at is null or pf.expires_at > now()),
      false
    ) as plan_enabled,
    o.enabled,
    o.reason,
    o.starts_at,
    o.expires_at,
    (o.id is not null and o.is_active and o.deleted_at is null
      and (o.starts_at is null or o.starts_at <= now())
      and (o.expires_at is null or o.expires_at > now())) as override_is_effective,
    case
      when o.id is not null and o.is_active and o.deleted_at is null
        and (o.starts_at is null or o.starts_at <= now())
        and (o.expires_at is null or o.expires_at > now())
      then o.enabled
      else coalesce(
        pf.enabled and pf.is_active and pf.deleted_at is null
        and (pf.starts_at is null or pf.starts_at <= now())
        and (pf.expires_at is null or pf.expires_at > now()), false
      )
    end as effective_enabled
  from public.features f
  left join subscription s on true
  left join public.plan_features pf
    on pf.plan_id = s.plan_id and pf.feature_id = f.id
  left join public.tenant_feature_overrides o
    on o.tenant_id = p_tenant_id and o.feature_id = f.id
    and o.is_active and o.deleted_at is null
  where f.is_active and f.deleted_at is null
  order by f.module, f.name;
end
$function$;

create or replace function public.platform_admin_get_tenant_limits(
  p_tenant_id uuid
)
returns table (
  limit_key text,
  plan_value numeric,
  override_value numeric,
  override_reason text,
  override_starts_at timestamptz,
  override_expires_at timestamptz,
  override_is_effective boolean,
  effective_value numeric
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return query
  with subscription as (
    select s.plan_id
    from public.tenant_subscriptions s
    where s.tenant_id = p_tenant_id and s.is_active and s.deleted_at is null
    order by s.created_at desc limit 1
  ), keys as (
    select l.key
    from public.plan_limits l join subscription s on s.plan_id = l.plan_id
    where l.is_active and l.deleted_at is null
    union
    select o.key from public.tenant_limit_overrides o
    where o.tenant_id = p_tenant_id and o.is_active and o.deleted_at is null
  )
  select
    k.key,
    case when l.is_active and l.deleted_at is null
      and (l.starts_at is null or l.starts_at <= now())
      and (l.expires_at is null or l.expires_at > now()) then l.value end,
    o.value,
    o.reason,
    o.starts_at,
    o.expires_at,
    (o.id is not null and o.is_active and o.deleted_at is null
      and (o.starts_at is null or o.starts_at <= now())
      and (o.expires_at is null or o.expires_at > now())),
    case
      when o.id is not null and o.is_active and o.deleted_at is null
        and (o.starts_at is null or o.starts_at <= now())
        and (o.expires_at is null or o.expires_at > now()) then o.value
      when l.is_active and l.deleted_at is null
        and (l.starts_at is null or l.starts_at <= now())
        and (l.expires_at is null or l.expires_at > now()) then l.value
      else null
    end
  from keys k
  left join subscription s on true
  left join public.plan_limits l on l.plan_id = s.plan_id and l.key = k.key
  left join public.tenant_limit_overrides o
    on o.tenant_id = p_tenant_id and o.key = k.key
    and o.is_active and o.deleted_at is null
  order by k.key;
end
$function$;

create or replace function public.platform_admin_set_tenant_subscription(
  p_tenant_id uuid, p_plan_id uuid, p_reason text default null
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return public.platform_set_tenant_subscription(
    p_tenant_id, p_plan_id, 'active', p_reason
  );
end
$function$;

create or replace function public.platform_admin_set_tenant_feature_override(
  p_tenant_id uuid, p_feature_id uuid, p_enabled boolean,
  p_reason text default null, p_expires_at timestamptz default null
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return public.platform_set_tenant_feature_override(
    p_tenant_id, p_feature_id, p_enabled, p_reason, null, p_expires_at
  );
end
$function$;

create or replace function public.platform_admin_remove_tenant_feature_override(
  p_tenant_id uuid, p_feature_id uuid, p_reason text default null
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  perform public.platform_remove_tenant_feature_override(
    p_tenant_id, p_feature_id, p_reason
  );
end
$function$;

create or replace function public.platform_admin_set_tenant_limit_override(
  p_tenant_id uuid, p_key text, p_value numeric,
  p_reason text default null, p_expires_at timestamptz default null
)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  return public.platform_set_tenant_limit_override(
    p_tenant_id, p_key, p_value, p_reason, null, p_expires_at
  );
end
$function$;

create or replace function public.platform_admin_remove_tenant_limit_override(
  p_tenant_id uuid, p_key text, p_reason text default null
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.require_active_platform_admin();
  perform public.platform_remove_tenant_limit_override(
    p_tenant_id, p_key, p_reason
  );
end
$function$;

do $grants$
declare signature text;
begin
  foreach signature in array array[
    'public.platform_admin_get_tenant_subscription(uuid)',
    'public.platform_admin_get_tenant_features(uuid)',
    'public.platform_admin_get_tenant_limits(uuid)',
    'public.platform_admin_set_tenant_subscription(uuid,uuid,text)',
    'public.platform_admin_set_tenant_feature_override(uuid,uuid,boolean,text,timestamptz)',
    'public.platform_admin_remove_tenant_feature_override(uuid,uuid,text)',
    'public.platform_admin_set_tenant_limit_override(uuid,text,numeric,text,timestamptz)',
    'public.platform_admin_remove_tenant_limit_override(uuid,text,text)'
  ] loop
    execute format('revoke all on function %s from public', signature);
    execute format('revoke all on function %s from anon', signature);
    execute format('grant execute on function %s to authenticated', signature);
    execute format('grant execute on function %s to service_role', signature);
  end loop;
end
$grants$;
