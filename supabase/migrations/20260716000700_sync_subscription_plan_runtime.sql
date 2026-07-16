-- Keep the compatibility tenant plan synchronized with the authoritative
-- active subscription, regardless of whether the plan changed through
-- billing verification or the subscription administration screen.

create or replace function public.sync_tenant_plan_from_subscription()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  target_plan_key text;
begin
  if not new.is_active or new.deleted_at is not null then
    return new;
  end if;

  select p.key into target_plan_key
  from public.plans p
  where p.id = new.plan_id
    and p.is_active
    and p.deleted_at is null;

  if target_plan_key is not null then
    update public.tenants
    set plan = target_plan_key
    where id = new.tenant_id
      and plan is distinct from target_plan_key;
  end if;

  return new;
end
$function$;

drop trigger if exists tenant_subscriptions_sync_tenant_plan
on public.tenant_subscriptions;

create trigger tenant_subscriptions_sync_tenant_plan
after insert or update of plan_id, is_active, deleted_at
on public.tenant_subscriptions
for each row execute function public.sync_tenant_plan_from_subscription();

update public.tenants t
set plan = p.key
from public.tenant_subscriptions s
join public.plans p on p.id = s.plan_id
where s.tenant_id = t.id
  and s.is_active
  and s.deleted_at is null
  and p.is_active
  and p.deleted_at is null
  and t.plan is distinct from p.key;

revoke all on function public.sync_tenant_plan_from_subscription()
from public, anon, authenticated;
