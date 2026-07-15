-- Run against a disposable/local database after applying all migrations.
begin;

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000321',
   'Package 3 Starter', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000322',
   'Package 3 Business', 'retail', 2, 'business', 'active', true),
  ('00000000-0000-4000-8000-000000000323',
   'Package 3 Enterprise', 'retail', 3, 'enterprise', 'suspended', true),
  ('00000000-0000-4000-8000-000000000324',
   'Package 3 Unknown', 'retail', 4, 'legacy_plan', 'active', true);

do $test$
declare
  subscription_count_after_first bigint;
  plan_count_before bigint;
  feature_count_before bigint;
  plan_feature_count_before bigint;
  plan_limit_count_before bigint;
begin
  select count(*) into plan_count_before from public.plans;
  select count(*) into feature_count_before from public.features;
  select count(*) into plan_feature_count_before from public.plan_features;
  select count(*) into plan_limit_count_before from public.plan_limits;

  perform public.sync_compatibility_tenant_subscriptions();

  if (select count(*)
      from public.tenant_subscriptions s
      join public.tenants t on t.id = s.tenant_id
      join public.plans p on p.id = s.plan_id
      where t.id in (
        '00000000-0000-4000-8000-000000000321',
        '00000000-0000-4000-8000-000000000322',
        '00000000-0000-4000-8000-000000000323'
      )
        and s.is_active and s.deleted_at is null
        and p.key = t.plan) <> 3 then
    raise exception 'Not every valid tenant received its matching subscription';
  end if;

  select count(*) into subscription_count_after_first
  from public.tenant_subscriptions;
  perform public.sync_compatibility_tenant_subscriptions();

  if (select count(*) from public.tenant_subscriptions) <>
       subscription_count_after_first then
    raise exception 'Repeated subscription backfill created duplicates';
  end if;

  if exists (
    select tenant_id, count(*)
    from public.tenant_subscriptions
    where is_active and deleted_at is null
    group by tenant_id
    having count(*) > 1
  ) then
    raise exception 'A tenant has duplicate active subscriptions';
  end if;

  if not exists (
    select 1 from public.report_unknown_tenant_plans()
    where tenant_id = '00000000-0000-4000-8000-000000000324'
      and plan_value = 'legacy_plan'
  ) then
    raise exception 'Unknown tenant plan was not reported';
  end if;

  if exists (
    select 1 from public.tenant_subscriptions
    where tenant_id = '00000000-0000-4000-8000-000000000324'
  ) then
    raise exception 'Unknown tenant plan was silently converted';
  end if;

  if not exists (
    select 1 from public.tenants
    where id = '00000000-0000-4000-8000-000000000323'
      and plan = 'enterprise' and status = 'suspended'
  ) or not exists (
    select 1 from public.tenant_subscriptions s
    where s.tenant_id = '00000000-0000-4000-8000-000000000323'
      and s.status = 'suspended' and s.is_active
  ) then
    raise exception 'Tenant plan/status compatibility values were not preserved';
  end if;

  if (select count(*) from public.plans) <> plan_count_before
     or (select count(*) from public.features) <> feature_count_before
     or (select count(*) from public.plan_features) <> plan_feature_count_before
     or (select count(*) from public.plan_limits) <> plan_limit_count_before then
    raise exception 'Package Patch 3 changed package defaults or feature availability';
  end if;
end
$test$;

rollback;
