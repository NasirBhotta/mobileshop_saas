-- Package Patch 3: mirror the current tenants.plan compatibility value into
-- tenant_subscriptions. tenants.plan remains unchanged and authoritative at runtime.

create or replace function public.report_unknown_tenant_plans()
returns table (tenant_id uuid, plan_value text)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select t.id, t.plan
  from public.tenants t
  where t.plan is null
     or t.plan not in ('starter', 'business', 'enterprise')
  order by t.id
$function$;

revoke all on function public.report_unknown_tenant_plans() from public;
revoke all on function public.report_unknown_tenant_plans() from anon;
revoke all on function public.report_unknown_tenant_plans() from authenticated;

create or replace function public.sync_compatibility_tenant_subscriptions()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  unknown_count bigint;
  unknown_values text;
  unknown_sample_ids text;
  mismatched_count bigint;
begin
  insert into public.tenant_subscriptions (
    tenant_id,
    plan_id,
    status,
    reason,
    is_active,
    deleted_at
  )
  select
    t.id,
    p.id,
    t.status,
    'Package Patch 3 compatibility backfill',
    true,
    null
  from public.tenants t
  join public.plans p on p.key = t.plan
  where t.plan in ('starter', 'business', 'enterprise')
    and not exists (
      select 1
      from public.tenant_subscriptions s
      where s.tenant_id = t.id
        and s.is_active
        and s.deleted_at is null
    )
  on conflict do nothing;

  select count(*) into unknown_count
  from public.report_unknown_tenant_plans();

  if unknown_count > 0 then
    select string_agg(value_to_report, ', ' order by value_to_report)
    into unknown_values
    from (
      select distinct coalesce(r.plan_value, '<null>') as value_to_report
      from public.report_unknown_tenant_plans() r
      limit 20
    ) values_to_report;

    select string_agg(r.tenant_id::text, ', ' order by r.tenant_id::text)
    into unknown_sample_ids
    from (
      select tenant_id
      from public.report_unknown_tenant_plans()
      order by tenant_id
      limit 10
    ) r;

    raise warning using message = format(
      'Package Patch 3 skipped %s tenants with unknown plan values [%s]. Sample tenant IDs: %s',
      unknown_count,
      coalesce(unknown_values, '(none)'),
      coalesce(unknown_sample_ids, '(none)')
    );
  end if;

  select count(*) into mismatched_count
  from public.tenants t
  join public.tenant_subscriptions s
    on s.tenant_id = t.id and s.is_active and s.deleted_at is null
  join public.plans p on p.id = s.plan_id
  where t.plan in ('starter', 'business', 'enterprise')
    and p.key <> t.plan;

  if mismatched_count > 0 then
    raise warning
      'Package Patch 3 preserved % existing active subscriptions that differ from tenants.plan',
      mismatched_count;
  end if;
end
$function$;

revoke all on function public.sync_compatibility_tenant_subscriptions() from public;
revoke all on function public.sync_compatibility_tenant_subscriptions() from anon;
revoke all on function public.sync_compatibility_tenant_subscriptions() from authenticated;

select public.sync_compatibility_tenant_subscriptions();
