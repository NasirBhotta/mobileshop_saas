-- Allow a platform admin to stop renewal without revoking access before the
-- already-paid billing period ends. Immediate cancellation remains available
-- through the existing `cancel` action.

alter table public.tenant_subscriptions
  add column if not exists cancel_at_period_end boolean not null default false,
  add column if not exists cancellation_requested_at timestamptz,
  add column if not exists cancellation_reason text;

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
  effective_billing_cycle text;
  calculated_until timestamptz;
  renewal_start timestamptz;
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
    'cancel', 'cancel_at_period_end', 'undo_cancel_at_period_end',
    'renew', 'suspend', 'grace'
  ) then
    raise exception using errcode = '22023', message = 'Unsupported subscription action.';
  end if;

  if action in ('trial_start', 'trial_extend', 'grace')
     and p_until is null then
    raise exception using errcode = '22023', message = 'An end date is required.';
  end if;

  if p_until is not null and p_until <= p_effective_at then
    raise exception using errcode = '22023', message = 'The end date must be after the effective date.';
  end if;

  effective_billing_cycle := lower(trim(coalesce(p_billing_cycle, s.billing_cycle)));
  if effective_billing_cycle not in ('monthly', 'annual') then
    raise exception using errcode = '22023', message = 'Billing cycle must be monthly or annual.';
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

  if action = 'cancel_at_period_end' then
    if s.status <> 'active' then
      raise exception using errcode = '22023', message = 'Only an active subscription can be scheduled for cancellation.';
    end if;

    if s.expires_at is null or s.expires_at <= now() then
      raise exception using errcode = '22023', message = 'A future billing-period end date is required.';
    end if;

    update public.tenant_subscriptions
    set cancel_at_period_end = true,
        cancellation_requested_at = now(),
        cancellation_reason = nullif(trim(p_reason), '')
    where id = s.id;

    insert into public.entitlement_audit_logs (
      tenant_id, action, entity_type, entity_id, reason,
      previous_value, new_value
    ) values (
      p_tenant_id, 'billing.subscription_cancel_at_period_end',
      'tenant_subscription', s.id, nullif(trim(p_reason), ''),
      jsonb_build_object(
        'status', s.status,
        'cancel_at_period_end', s.cancel_at_period_end,
        'expires_at', s.expires_at
      ),
      jsonb_build_object(
        'status', s.status,
        'cancel_at_period_end', true,
        'expires_at', s.expires_at
      )
    );
    return;
  end if;

  if action = 'undo_cancel_at_period_end' then
    if not s.cancel_at_period_end then
      raise exception using errcode = '22023', message = 'This subscription has no scheduled cancellation.';
    end if;

    update public.tenant_subscriptions
    set cancel_at_period_end = false,
        cancellation_requested_at = null,
        cancellation_reason = null
    where id = s.id;

    insert into public.entitlement_audit_logs (
      tenant_id, action, entity_type, entity_id, reason,
      previous_value, new_value
    ) values (
      p_tenant_id, 'billing.subscription_cancellation_reversed',
      'tenant_subscription', s.id, nullif(trim(p_reason), ''),
      jsonb_build_object(
        'status', s.status,
        'cancel_at_period_end', true,
        'expires_at', s.expires_at
      ),
      jsonb_build_object(
        'status', s.status,
        'cancel_at_period_end', false,
        'expires_at', s.expires_at
      )
    );
    return;
  end if;

  calculated_until := p_until;
  if action = 'activate' then
    calculated_until := p_effective_at + case effective_billing_cycle
      when 'annual' then interval '1 year'
      else interval '1 month'
    end;
  elsif action = 'renew' then
    renewal_start := greatest(p_effective_at, coalesce(s.expires_at, p_effective_at));
    calculated_until := renewal_start + case effective_billing_cycle
      when 'annual' then interval '1 year'
      else interval '1 month'
    end;
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
      billing_cycle = effective_billing_cycle,
      starts_at = case when action = 'activate' then p_effective_at else starts_at end,
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
      renews_at = case when action in ('activate', 'renew') then calculated_until else renews_at end,
      grace_ends_at = case
        when action = 'grace' then p_until
        when action in ('activate', 'renew', 'cancel', 'suspend') then null
        else grace_ends_at
      end,
      expires_at = case
        when action in ('cancel', 'trial_end') then p_effective_at
        when action in ('activate', 'renew') then calculated_until
        when action in ('trial_start', 'trial_extend') then null
        else expires_at
      end,
      cancel_at_period_end = case
        when action in ('trial_start', 'trial_extend', 'activate', 'renew', 'cancel') then false
        else cancel_at_period_end
      end,
      cancellation_requested_at = case
        when action in ('trial_start', 'trial_extend', 'activate', 'renew', 'cancel') then null
        else cancellation_requested_at
      end,
      cancellation_reason = case
        when action in ('trial_start', 'trial_extend', 'activate', 'renew', 'cancel') then null
        else cancellation_reason
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
    jsonb_build_object(
      'status', s.status,
      'cancel_at_period_end', s.cancel_at_period_end
    ),
    jsonb_build_object(
      'status', next_status,
      'until', calculated_until,
      'billing_cycle', effective_billing_cycle,
      'cancel_at_period_end', false
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

-- Include cancellation scheduling in the admin billing summary. PostgreSQL
-- requires dropping the function when its table return type changes.
drop function if exists public.platform_get_billing_summary(uuid);

create function public.platform_get_billing_summary(p_tenant_id uuid)
returns table (
  subscription_id uuid,
  plan text,
  subscription_status text,
  billing_cycle text,
  trial_starts_at timestamptz,
  trial_ends_at timestamptz,
  renewal_date timestamptz,
  grace_ends_at timestamptz,
  expires_at timestamptz,
  cancel_at_period_end boolean,
  cancellation_requested_at timestamptz,
  outstanding_amount numeric,
  currency text
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
    s.id,
    p.name,
    s.status,
    s.billing_cycle,
    s.trial_starts_at,
    s.trial_ends_at,
    s.renews_at,
    s.grace_ends_at,
    s.expires_at,
    s.cancel_at_period_end,
    s.cancellation_requested_at,
    coalesce(sum(i.amount) filter (where i.status = 'open'), 0)::numeric,
    'PKR'::text
  from public.tenant_subscriptions s
  join public.plans p on p.id = s.plan_id
  left join public.billing_invoices i on i.subscription_id = s.id
  where s.tenant_id = p_tenant_id
    and s.is_active
    and s.deleted_at is null
  group by s.id, p.name;
end
$function$;

revoke all on function public.platform_get_billing_summary(uuid)
from public, anon;

grant execute on function public.platform_get_billing_summary(uuid)
to authenticated, service_role;
