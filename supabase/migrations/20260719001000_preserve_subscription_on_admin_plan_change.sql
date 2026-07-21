-- Changing a package is not a subscription activation. Preserve the current
-- lifecycle row (status, paid-through date, billing cycle and invoice links)
-- and update only its plan. A tenant without a subscription starts pending.

create or replace function public.platform_admin_set_tenant_subscription(
  p_tenant_id uuid,
  p_plan_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_id uuid := public.require_active_platform_admin();
  audit_actor_id uuid;
  current_subscription public.tenant_subscriptions%rowtype;
  result_id uuid;
begin
  if not exists (select 1 from public.tenants where id = p_tenant_id) then
    raise exception using errcode = 'P0002', message = 'Tenant not found.';
  end if;

  if not exists (
    select 1
    from public.plans
    where id = p_plan_id and is_active and deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'Active plan not found.';
  end if;

  select * into current_subscription
  from public.tenant_subscriptions
  where tenant_id = p_tenant_id
    and is_active
    and deleted_at is null
  for update;

  if found then
    result_id := current_subscription.id;
    if current_subscription.plan_id = p_plan_id then
      return result_id;
    end if;

    update public.tenant_subscriptions
    set plan_id = p_plan_id,
        reason = nullif(trim(p_reason), '')
    where id = result_id;
  else
    insert into public.tenant_subscriptions (
      tenant_id, plan_id, status, reason, is_active, deleted_at
    ) values (
      p_tenant_id, p_plan_id, 'pending_activation',
      coalesce(
        nullif(trim(p_reason), ''),
        'Awaiting platform trial or subscription activation'
      ),
      true, null
    )
    returning id into result_id;
  end if;

  select actor_id into audit_actor_id
  where exists (select 1 from public.users where id = actor_id);

  insert into public.entitlement_audit_logs (
    tenant_id, actor_user_id, action, entity_type, entity_id,
    reason, previous_value, new_value
  ) values (
    p_tenant_id,
    audit_actor_id,
    case
      when current_subscription.id is null then 'tenant.plan_assigned'
      else 'tenant.plan_changed'
    end,
    'tenant_subscription',
    result_id,
    nullif(trim(p_reason), ''),
    case
      when current_subscription.id is null then null
      else jsonb_build_object(
        'plan_id', current_subscription.plan_id,
        'status', current_subscription.status,
        'expires_at', current_subscription.expires_at
      )
    end,
    jsonb_build_object(
      'plan_id', p_plan_id,
      'status', coalesce(current_subscription.status, 'pending_activation'),
      'expires_at', current_subscription.expires_at
    )
  );

  return result_id;
end
$function$;

revoke all on function public.platform_admin_set_tenant_subscription(
  uuid, uuid, text
) from public, anon;
grant execute on function public.platform_admin_set_tenant_subscription(
  uuid, uuid, text
) to authenticated, service_role;
