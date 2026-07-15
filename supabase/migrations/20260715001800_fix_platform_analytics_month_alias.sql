-- Patch 8 repair: avoid MONTH as a generated-series column alias.

create or replace function public.platform_get_analytics()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  result jsonb;
begin
  perform public.require_active_platform_admin();
  select jsonb_build_object(
    'total_tenants',(select count(*) from public.tenants),
    'active_tenants',(select count(*) from public.tenants where lower(status)='active'),
    'suspended_tenants',(select count(*) from public.tenants where lower(status)='suspended'),
    'monthly_revenue',(select coalesce(sum(amount),0) from public.billing_payments where status='verified' and paid_at>=date_trunc('month',now())),
    'currency','PKR',
    'unpaid_invoice_count',(select count(*) from public.billing_invoices where status='open'),
    'unpaid_invoice_amount',(select coalesce(sum(amount),0) from public.billing_invoices where status='open'),
    'active_trials',(select count(*) from public.tenant_subscriptions where is_active and deleted_at is null and status='trialing' and trial_ends_at>now()),
    'upcoming_renewals',(select count(*) from public.tenant_subscriptions where is_active and deleted_at is null and renews_at>=now() and renews_at<now()+interval '30 days'),
    'tenant_growth',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object('month',month_label,'count',tenant_count)
          order by month_start
        ),
        '[]'::jsonb
      )
      from (
        select
          series.month_start,
          to_char(series.month_start,'YYYY-MM') as month_label,
          count(t.id) as tenant_count
        from generate_series(
          date_trunc('month',now())-interval '5 months',
          date_trunc('month',now()),
          interval '1 month'
        ) as series(month_start)
        left join public.tenants t
          on t.created_at>=series.month_start
         and t.created_at<series.month_start+interval '1 month'
        group by series.month_start
      ) growth
    ),
    'plan_distribution',(select coalesce(jsonb_agg(jsonb_build_object('name',plan,'count',count) order by plan),'[]'::jsonb) from
      (select coalesce(nullif(trim(plan),''),'unknown') plan,count(*) count from public.tenants group by 1) x),
    'feature_usage',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'count',count) order by count desc,name),'[]'::jsonb) from
      (select f.key name,count(distinct s.tenant_id) count from public.features f left join public.plan_features pf on pf.feature_id=f.id and pf.enabled and pf.is_active and pf.deleted_at is null
       left join public.tenant_subscriptions s on s.plan_id=pf.plan_id and s.is_active and s.deleted_at is null where f.is_active and f.deleted_at is null group by f.key) x),
    'addon_usage',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'count',count) order by count desc,name),'[]'::jsonb) from
      (select a.name,count(ta.id) filter(where ta.enabled and ta.status='active' and ta.starts_at<=now() and (ta.expires_at is null or ta.expires_at>now())) count
       from public.addon_definitions a left join public.tenant_addons ta on ta.addon_id=a.id where a.is_active group by a.id) x)
  ) into result;
  return result;
end
$function$;

revoke all on function public.platform_get_analytics() from public, anon;
grant execute on function public.platform_get_analytics()
to authenticated, service_role;
