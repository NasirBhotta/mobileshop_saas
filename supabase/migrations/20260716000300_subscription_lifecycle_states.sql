-- Introduce an explicit admin-controlled subscription lifecycle without
-- changing any tenant feature, permission, plan-feature, or limit logic.

create or replace function public.ensure_compatibility_tenant_subscription()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  target_plan_id uuid;
begin
  if new.plan not in ('starter', 'business', 'enterprise') then
    return new;
  end if;

  if exists (
    select 1
    from public.tenant_subscriptions s
    where s.tenant_id = new.id
      and s.is_active
      and s.deleted_at is null
  ) then
    return new;
  end if;

  select p.id into target_plan_id
  from public.plans p
  where p.key = new.plan
    and p.is_active
    and p.deleted_at is null;

  if target_plan_id is null then
    raise exception using
      errcode = '23503',
      message = format('Active package plan not found for tenant plan %s.', new.plan);
  end if;

  insert into public.tenant_subscriptions (
    tenant_id, plan_id, status, reason, is_active, deleted_at
  ) values (
    new.id, target_plan_id, 'pending_activation',
    'Awaiting platform trial or subscription activation', true, null
  ) on conflict do nothing;

  return new;
end
$function$;

create or replace function public.platform_manage_subscription(
  p_tenant_id uuid,
  p_action text,
  p_effective_at timestamptz default now(),
  p_until timestamptz default null,
  p_billing_cycle text default null,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor uuid;
  s public.tenant_subscriptions%rowtype;
  action text := lower(trim(p_action));
  next_status text;
begin
  actor := public.require_active_platform_admin();

  select * into s
  from public.tenant_subscriptions
  where tenant_id = p_tenant_id
    and is_active
    and deleted_at is null
  for update;

  if s.id is null then
    raise exception using errcode = 'P0002', message = 'Current subscription not found.';
  end if;

  if action not in (
    'trial_start', 'trial_extend', 'trial_end', 'activate',
    'cancel', 'renew', 'suspend', 'grace'
  ) then
    raise exception using errcode = '22023', message = 'Unsupported subscription action.';
  end if;

  if action in ('trial_start', 'trial_extend', 'grace', 'renew')
     and p_until is null then
    raise exception using errcode = '22023', message = 'An end or renewal date is required.';
  end if;

  if p_until is not null and p_until <= p_effective_at then
    raise exception using errcode = '22023', message = 'The end date must be after the effective date.';
  end if;

  if action = 'trial_start' and s.status not in (
    'pending_activation', 'trial_expired', 'cancelled'
  ) then
    raise exception using errcode = '22023', message = 'A trial can only start for a pending, expired, or cancelled subscription.';
  elsif action = 'trial_extend' and s.status not in ('trialing', 'trial_expired') then
    raise exception using errcode = '22023', message = 'Only a trialing or expired subscription can be extended.';
  elsif action = 'trial_end' and s.status <> 'trialing' then
    raise exception using errcode = '22023', message = 'Only an active trial can be ended.';
  elsif action = 'grace' and s.status not in ('active', 'grace_period') then
    raise exception using errcode = '22023', message = 'Grace is only available for active subscriptions.';
  elsif action = 'renew' and s.status not in ('active', 'grace_period', 'cancelled') then
    raise exception using errcode = '22023', message = 'This subscription cannot be renewed from its current state.';
  end if;

  next_status := case
    when action in ('trial_start', 'trial_extend') then 'trialing'
    when action = 'trial_end' then 'trial_expired'
    when action in ('activate', 'renew') then 'active'
    when action = 'cancel' then 'cancelled'
    when action = 'suspend' then 'suspended'
    when action = 'grace' then 'grace_period'
  end;

  update public.tenant_subscriptions
  set status = next_status,
      billing_cycle = coalesce(nullif(trim(p_billing_cycle), ''), billing_cycle),
      trial_starts_at = case
        when action = 'trial_start' then p_effective_at
        when action = 'trial_extend' and s.status = 'trial_expired' then p_effective_at
        else trial_starts_at
      end,
      trial_ends_at = case
        when action in ('trial_start', 'trial_extend') then p_until
        when action = 'trial_end' then p_effective_at
        else trial_ends_at
      end,
      renews_at = case when action = 'renew' then p_until else renews_at end,
      grace_ends_at = case
        when action = 'grace' then p_until
        when action in ('activate', 'renew', 'cancel', 'suspend') then null
        else grace_ends_at
      end,
      expires_at = case
        when action in ('cancel', 'trial_end') then p_effective_at
        when action in ('activate', 'renew') then p_until
        when action in ('trial_start', 'trial_extend') then null
        else expires_at
      end,
      reason = nullif(trim(p_reason), '')
  where id = s.id;

  update public.tenants
  set status = case
    when action = 'suspend' then 'suspended'
    when action in ('trial_start', 'trial_extend', 'activate', 'renew', 'grace') then 'active'
    else status
  end
  where id = p_tenant_id;

  insert into public.entitlement_audit_logs (
    tenant_id, action, entity_type, entity_id, reason,
    previous_value, new_value
  ) values (
    p_tenant_id, 'billing.subscription_' || action,
    'tenant_subscription', s.id, nullif(trim(p_reason), ''),
    jsonb_build_object('status', s.status),
    jsonb_build_object(
      'status', next_status,
      'until', p_until,
      'billing_cycle', coalesce(nullif(trim(p_billing_cycle), ''), s.billing_cycle)
    )
  );
end
$function$;

revoke all on function public.platform_manage_subscription(
  uuid, text, timestamptz, timestamptz, text, text
) from public, anon;

grant execute on function public.platform_manage_subscription(
  uuid, text, timestamptz, timestamptz, text, text
) to authenticated, service_role;

-- Existing tenants retain their current statuses and access. Only subscription
-- rows created by the trigger after this migration start pending activation.
