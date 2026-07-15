-- Keep compatibility tenants.plan and the entitlement subscription source in sync
-- for tenants created after the original subscription backfill.

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
  where p.key = new.plan and p.is_active and p.deleted_at is null;

  if target_plan_id is null then
    raise exception using
      errcode = '23503',
      message = format('Active package plan not found for tenant plan %s.', new.plan);
  end if;

  insert into public.tenant_subscriptions (
    tenant_id, plan_id, status, reason, is_active, deleted_at
  ) values (
    new.id, target_plan_id, 'active',
    'Automatic tenant signup subscription', true, null
  ) on conflict do nothing;

  return new;
end
$function$;

drop trigger if exists tenants_ensure_compatibility_subscription
on public.tenants;
create trigger tenants_ensure_compatibility_subscription
after insert on public.tenants
for each row execute function public.ensure_compatibility_tenant_subscription();

-- Repair tenants created after Package Patch 3 and before this trigger.
insert into public.tenant_subscriptions (
  tenant_id, plan_id, status, reason, is_active, deleted_at
)
select
  t.id, p.id, 'active',
  'Automatic missing subscription repair', true, null
from public.tenants t
join public.plans p on p.key = t.plan and p.is_active and p.deleted_at is null
where t.plan in ('starter', 'business', 'enterprise')
  and not exists (
    select 1 from public.tenant_subscriptions s
    where s.tenant_id = t.id and s.is_active and s.deleted_at is null
  )
on conflict do nothing;

revoke all on function public.ensure_compatibility_tenant_subscription()
from public, anon, authenticated;
