-- Run against a disposable/local database after applying all migrations.
begin;

do $test$
declare
  plan_count_before bigint;
  feature_count_before bigint;
  plan_feature_count_before bigint;
  plan_limit_count_before bigint;
begin
  select count(*) into plan_count_before from public.plans;
  select count(*) into feature_count_before from public.features;
  select count(*) into plan_feature_count_before from public.plan_features;
  select count(*) into plan_limit_count_before from public.plan_limits;

  perform public.sync_package_presets();

  if (select count(*) from public.plans) <> plan_count_before
     or (select count(*) from public.features) <> feature_count_before
     or (select count(*) from public.plan_features) <> plan_feature_count_before
     or (select count(*) from public.plan_limits) <> plan_limit_count_before then
    raise exception 'Repeated package preset sync created duplicate rows';
  end if;

  if (select count(*) from public.plans
      where key in ('starter', 'business', 'enterprise')) <> 3 then
    raise exception 'Starter, Business and Enterprise were not seeded once';
  end if;

  if exists (
    select lower(key) from public.plans
    where key in ('starter', 'business', 'enterprise')
    group by lower(key) having count(*) > 1
  ) or exists (
    select lower(key) from public.features
    group by lower(key) having count(*) > 1
  ) then
    raise exception 'Package Patch 2 produced duplicate plan or feature keys';
  end if;

  if (select count(*) from public.features where key in (
        'dashboard.access', 'branches.access', 'users.access',
        'inventory.access', 'pos.access', 'customers.access',
        'repairs.access', 'suppliers.access', 'purchases.access',
        'expenses.access', 'accounts.access', 'reports.access',
        'settings.access', 'receipts.access', 'purchases.procurement',
        'inventory.csv_import', 'inventory.bulk_pricing', 'reports.export',
        'reports.scheduling', 'expenses.history'
      )) <> 20 then
    raise exception 'Commercial feature catalog is incomplete';
  end if;

  if exists (
    select 1
    from public.plans p
    cross join (values
      ('purchases.procurement'),
      ('inventory.csv_import'),
      ('inventory.bulk_pricing')
    ) required(feature_key)
    where p.key in ('starter', 'business', 'enterprise')
      and not exists (
        select 1 from public.plan_features pf
        join public.features f on f.id = pf.feature_id
        where pf.plan_id = p.id and f.key = required.feature_key
          and pf.enabled and pf.is_active and pf.deleted_at is null
      )
  ) then
    raise exception 'Procurement, CSV import or bulk pricing is not enabled for every plan';
  end if;

  if (select count(*)
      from public.plan_features pf
      join public.plans p on p.id = pf.plan_id
      join public.features f on f.id = pf.feature_id
      where p.key in ('starter', 'business', 'enterprise')
        and f.key in ('reports.export', 'reports.scheduling')) <> 6 then
    raise exception 'Report export/scheduling defaults are incomplete';
  end if;

  if exists (
    select 1
    from public.plans p
    cross join (values ('reports.export'), ('reports.scheduling')) required(feature_key)
    join public.features f on f.key = required.feature_key
    join public.plan_features pf on pf.plan_id = p.id and pf.feature_id = f.id
    where p.key in ('starter', 'business', 'enterprise')
      and pf.enabled <> (p.key in ('business', 'enterprise'))
  ) then
    raise exception 'Report export/scheduling defaults do not match package presets';
  end if;

  if exists (
    select 1
    from public.plans p
    left join public.plan_limits l
      on l.plan_id = p.id and l.key = 'expenses.history_days'
    where p.key in ('starter', 'business', 'enterprise')
      and l.value is distinct from case p.key
        when 'starter' then 30::numeric
        when 'business' then 365::numeric
        when 'enterprise' then (-1)::numeric
      end
  ) then
    raise exception 'Expense history limits do not match 30/365/unlimited defaults';
  end if;
end
$test$;

rollback;
