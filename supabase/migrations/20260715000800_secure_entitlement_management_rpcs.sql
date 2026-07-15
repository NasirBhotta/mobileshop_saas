-- Package Patch 6: trusted backend entitlement management operations.
-- Tenant clients remain read-only and tenants.plan remains untouched.

create or replace function public.audit_entitlement_table_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  previous_row jsonb;
  next_row jsonb;
  audit_tenant_id uuid;
  audit_entity_id uuid;
  audit_actor_id uuid;
begin
  previous_row := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  next_row := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  audit_tenant_id := nullif(
    coalesce(next_row ->> 'tenant_id', previous_row ->> 'tenant_id'),
    ''
  )::uuid;
  audit_entity_id := nullif(
    coalesce(next_row ->> 'id', previous_row ->> 'id'),
    ''
  )::uuid;
  audit_actor_id := auth.uid();
  if audit_actor_id is not null and not exists (
    select 1 from public.users where id = audit_actor_id
  ) then
    audit_actor_id := null;
  end if;

  insert into public.entitlement_audit_logs (
    tenant_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    reason,
    previous_value,
    new_value
  ) values (
    audit_tenant_id,
    audit_actor_id,
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    audit_entity_id,
    coalesce(next_row ->> 'reason', previous_row ->> 'reason'),
    previous_row,
    next_row
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$function$;

revoke all on function public.audit_entitlement_table_change() from public;
revoke all on function public.audit_entitlement_table_change() from anon;
revoke all on function public.audit_entitlement_table_change() from authenticated;

do $migration$
declare
  table_name text;
begin
  foreach table_name in array array[
    'plans',
    'features',
    'plan_features',
    'plan_limits',
    'tenant_subscriptions',
    'tenant_feature_overrides',
    'tenant_limit_overrides'
  ] loop
    execute format(
      'drop trigger if exists %I on public.%I',
      table_name || '_entitlement_audit',
      table_name
    );
    execute format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function public.audit_entitlement_table_change()',
      table_name || '_entitlement_audit',
      table_name
    );
  end loop;
end
$migration$;

create or replace function public.platform_upsert_plan(
  p_plan_id uuid,
  p_key text,
  p_name text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  result_id uuid;
begin
  if p_key is null or p_key !~ '^[a-z][a-z0-9_]*$' then
    raise exception using errcode = '22023', message = 'Invalid plan key.';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception using errcode = '22023', message = 'Plan name is required.';
  end if;

  if p_plan_id is null then
    insert into public.plans (key, name, description)
    values (p_key, trim(p_name), p_description)
    returning id into result_id;
  else
    update public.plans
    set key = p_key,
        name = trim(p_name),
        description = p_description
    where id = p_plan_id
    returning id into result_id;
    if result_id is null then
      raise exception using errcode = 'P0002', message = 'Plan not found.';
    end if;
  end if;

  return result_id;
end
$function$;

create or replace function public.platform_set_plan_active(
  p_plan_id uuid,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if p_is_active is null then
    raise exception using errcode = '22023', message = 'Plan active state is required.';
  end if;
  if not coalesce(p_is_active, false) and exists (
    select 1 from public.tenant_subscriptions s
    where s.plan_id = p_plan_id and s.is_active and s.deleted_at is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'Move active tenant subscriptions before deactivating this plan.';
  end if;

  update public.plans
  set is_active = p_is_active,
      deleted_at = case when p_is_active then null else now() end
  where id = p_plan_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Plan not found.';
  end if;
end
$function$;

create or replace function public.platform_upsert_feature(
  p_feature_id uuid,
  p_key text,
  p_module text,
  p_name text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  result_id uuid;
begin
  if p_key is null or p_key !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$' then
    raise exception using errcode = '22023', message = 'Invalid feature key.';
  end if;
  if p_module is null or length(trim(p_module)) = 0
     or p_name is null or length(trim(p_name)) = 0 then
    raise exception using
      errcode = '22023',
      message = 'Feature module and name are required.';
  end if;

  if p_feature_id is null then
    insert into public.features (key, module, name, description)
    values (p_key, trim(p_module), trim(p_name), p_description)
    returning id into result_id;
  else
    update public.features
    set key = p_key,
        module = trim(p_module),
        name = trim(p_name),
        description = p_description
    where id = p_feature_id
    returning id into result_id;
    if result_id is null then
      raise exception using errcode = 'P0002', message = 'Feature not found.';
    end if;
  end if;

  return result_id;
end
$function$;

create or replace function public.platform_set_feature_active(
  p_feature_id uuid,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if p_is_active is null then
    raise exception using errcode = '22023', message = 'Feature active state is required.';
  end if;
  update public.features
  set is_active = p_is_active,
      deleted_at = case when p_is_active then null else now() end
  where id = p_feature_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Feature not found.';
  end if;
end
$function$;

create or replace function public.platform_set_plan_feature(
  p_plan_id uuid,
  p_feature_id uuid,
  p_enabled boolean,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  result_id uuid;
begin
  if not exists (
    select 1 from public.plans
    where id = p_plan_id and is_active and deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Active plan not found.';
  end if;
  if not exists (
    select 1 from public.features
    where id = p_feature_id and is_active and deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Active feature not found.';
  end if;
  if p_enabled is null then
    raise exception using errcode = '22023', message = 'Feature enabled state is required.';
  end if;

  insert into public.plan_features (
    plan_id, feature_id, enabled, reason, is_active, deleted_at
  ) values (
    p_plan_id, p_feature_id, p_enabled, p_reason, true, null
  )
  on conflict (plan_id, feature_id) do update
  set enabled = excluded.enabled,
      reason = excluded.reason,
      is_active = true,
      deleted_at = null
  returning id into result_id;
  return result_id;
end
$function$;

create or replace function public.platform_set_plan_limit(
  p_plan_id uuid,
  p_key text,
  p_value numeric,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  result_id uuid;
begin
  if not exists (
    select 1 from public.plans
    where id = p_plan_id and is_active and deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Active plan not found.';
  end if;
  if p_key is null or p_key !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
     or p_value is null or p_value < -1 then
    raise exception using errcode = '22023', message = 'Invalid plan limit.';
  end if;

  insert into public.plan_limits (
    plan_id, key, value, reason, is_active, deleted_at
  ) values (
    p_plan_id, p_key, p_value, p_reason, true, null
  )
  on conflict (plan_id, key) do update
  set value = excluded.value,
      reason = excluded.reason,
      is_active = true,
      deleted_at = null
  returning id into result_id;
  return result_id;
end
$function$;

create or replace function public.platform_set_tenant_subscription(
  p_tenant_id uuid,
  p_plan_id uuid,
  p_status text default 'active',
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  current_subscription public.tenant_subscriptions%rowtype;
  result_id uuid;
begin
  if not exists (select 1 from public.tenants where id = p_tenant_id) then
    raise exception using errcode = '22023', message = 'Tenant not found.';
  end if;
  if not exists (
    select 1 from public.plans
    where id = p_plan_id and is_active and deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Active plan not found.';
  end if;
  if p_status is null or length(trim(p_status)) = 0 then
    raise exception using errcode = '22023', message = 'Subscription status is required.';
  end if;

  select * into current_subscription
  from public.tenant_subscriptions
  where tenant_id = p_tenant_id and is_active and deleted_at is null
  for update;

  if found and current_subscription.plan_id = p_plan_id then
    update public.tenant_subscriptions
    set status = trim(p_status), reason = p_reason
    where id = current_subscription.id
    returning id into result_id;
    return result_id;
  end if;

  if found then
    update public.tenant_subscriptions
    set is_active = false, deleted_at = now(), reason = p_reason
    where id = current_subscription.id;
  end if;

  insert into public.tenant_subscriptions (
    tenant_id, plan_id, status, reason, is_active, deleted_at
  ) values (
    p_tenant_id, p_plan_id, trim(p_status), p_reason, true, null
  ) returning id into result_id;
  return result_id;
end
$function$;

create or replace function public.platform_set_tenant_feature_override(
  p_tenant_id uuid,
  p_feature_id uuid,
  p_enabled boolean,
  p_reason text default null,
  p_starts_at timestamptz default null,
  p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  result_id uuid;
begin
  if not exists (select 1 from public.tenants where id = p_tenant_id) then
    raise exception using errcode = '22023', message = 'Tenant not found.';
  end if;
  if not exists (
    select 1 from public.features
    where id = p_feature_id and is_active and deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Active feature not found.';
  end if;
  if p_enabled is null then
    raise exception using errcode = '22023', message = 'Override enabled state is required.';
  end if;
  if p_expires_at is not null and p_starts_at is not null
     and p_expires_at <= p_starts_at then
    raise exception using errcode = '22023', message = 'Invalid override dates.';
  end if;

  select id into result_id
  from public.tenant_feature_overrides
  where tenant_id = p_tenant_id and feature_id = p_feature_id
    and is_active and deleted_at is null
  for update;

  if result_id is null then
    insert into public.tenant_feature_overrides (
      tenant_id, feature_id, enabled, reason, starts_at, expires_at
    ) values (
      p_tenant_id, p_feature_id, p_enabled, p_reason, p_starts_at, p_expires_at
    ) returning id into result_id;
  else
    update public.tenant_feature_overrides
    set enabled = p_enabled,
        reason = p_reason,
        starts_at = p_starts_at,
        expires_at = p_expires_at
    where id = result_id;
  end if;
  return result_id;
end
$function$;

create or replace function public.platform_remove_tenant_feature_override(
  p_tenant_id uuid,
  p_feature_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  update public.tenant_feature_overrides
  set is_active = false, deleted_at = now(), reason = p_reason
  where tenant_id = p_tenant_id and feature_id = p_feature_id
    and is_active and deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Active feature override not found.';
  end if;
end
$function$;

create or replace function public.platform_set_tenant_limit_override(
  p_tenant_id uuid,
  p_key text,
  p_value numeric,
  p_reason text default null,
  p_starts_at timestamptz default null,
  p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  result_id uuid;
begin
  if not exists (select 1 from public.tenants where id = p_tenant_id) then
    raise exception using errcode = '22023', message = 'Tenant not found.';
  end if;
  if p_key is null or p_key !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
     or p_value is null or p_value < -1 then
    raise exception using errcode = '22023', message = 'Invalid limit override.';
  end if;
  if p_expires_at is not null and p_starts_at is not null
     and p_expires_at <= p_starts_at then
    raise exception using errcode = '22023', message = 'Invalid override dates.';
  end if;

  select id into result_id
  from public.tenant_limit_overrides
  where tenant_id = p_tenant_id and key = p_key
    and is_active and deleted_at is null
  for update;

  if result_id is null then
    insert into public.tenant_limit_overrides (
      tenant_id, key, value, reason, starts_at, expires_at
    ) values (
      p_tenant_id, p_key, p_value, p_reason, p_starts_at, p_expires_at
    ) returning id into result_id;
  else
    update public.tenant_limit_overrides
    set value = p_value,
        reason = p_reason,
        starts_at = p_starts_at,
        expires_at = p_expires_at
    where id = result_id;
  end if;
  return result_id;
end
$function$;

create or replace function public.platform_remove_tenant_limit_override(
  p_tenant_id uuid,
  p_key text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  update public.tenant_limit_overrides
  set is_active = false, deleted_at = now(), reason = p_reason
  where tenant_id = p_tenant_id and key = p_key
    and is_active and deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Active limit override not found.';
  end if;
end
$function$;

do $grants$
declare
  signature text;
begin
  foreach signature in array array[
    'public.platform_upsert_plan(uuid,text,text,text)',
    'public.platform_set_plan_active(uuid,boolean)',
    'public.platform_upsert_feature(uuid,text,text,text,text)',
    'public.platform_set_feature_active(uuid,boolean)',
    'public.platform_set_plan_feature(uuid,uuid,boolean,text)',
    'public.platform_set_plan_limit(uuid,text,numeric,text)',
    'public.platform_set_tenant_subscription(uuid,uuid,text,text)',
    'public.platform_set_tenant_feature_override(uuid,uuid,boolean,text,timestamptz,timestamptz)',
    'public.platform_remove_tenant_feature_override(uuid,uuid,text)',
    'public.platform_set_tenant_limit_override(uuid,text,numeric,text,timestamptz,timestamptz)',
    'public.platform_remove_tenant_limit_override(uuid,text,text)'
  ] loop
    execute format('revoke all on function %s from public', signature);
    execute format('revoke all on function %s from anon', signature);
    execute format('revoke all on function %s from authenticated', signature);
    execute format('grant execute on function %s to service_role', signature);
  end loop;
end
$grants$;
