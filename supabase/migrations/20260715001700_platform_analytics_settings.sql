-- Admin Portal Patch 8: read-only platform analytics and audited global defaults.

create table if not exists public.platform_settings (
  singleton boolean primary key default true check (singleton),
  trial_duration_days integer not null default 14 check (trial_duration_days between 0 and 365),
  grace_period_days integer not null default 7 check (grace_period_days between 0 and 90),
  default_billing_cycle text not null default 'monthly' check (default_billing_cycle in ('monthly','annual')),
  default_currency text not null default 'PKR' check (default_currency ~ '^[A-Z]{3}$'),
  support_email text,
  support_phone text,
  maintenance_mode boolean not null default false,
  maintenance_message text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
insert into public.platform_settings(singleton) values(true)
on conflict (singleton) do nothing;
alter table public.platform_settings enable row level security;
revoke all on public.platform_settings from anon,authenticated;
grant all on public.platform_settings to service_role;

create or replace function public.platform_get_analytics()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare result jsonb; begin perform public.require_active_platform_admin();
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
  'tenant_growth',(select coalesce(jsonb_agg(jsonb_build_object('month',month_label,'count',tenant_count) order by month_start),'[]'::jsonb) from
    (select series.month_start,to_char(series.month_start,'YYYY-MM') as month_label,count(t.id) as tenant_count
     from generate_series(date_trunc('month',now())-interval '5 months',date_trunc('month',now()),interval '1 month') as series(month_start)
     left join public.tenants t on t.created_at>=series.month_start and t.created_at<series.month_start+interval '1 month'
     group by series.month_start) x),
  'plan_distribution',(select coalesce(jsonb_agg(jsonb_build_object('name',plan,'count',count) order by plan),'[]'::jsonb) from
    (select coalesce(nullif(trim(plan),''),'unknown') plan,count(*) count from public.tenants group by 1) x),
  'feature_usage',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'count',count) order by count desc,name),'[]'::jsonb) from
    (select f.key name,count(distinct s.tenant_id) count from public.features f left join public.plan_features pf on pf.feature_id=f.id and pf.enabled and pf.is_active and pf.deleted_at is null
     left join public.tenant_subscriptions s on s.plan_id=pf.plan_id and s.is_active and s.deleted_at is null where f.is_active and f.deleted_at is null group by f.key) x),
  'addon_usage',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'count',count) order by count desc,name),'[]'::jsonb) from
    (select a.name,count(ta.id) filter(where ta.enabled and ta.status='active' and ta.starts_at<=now() and (ta.expires_at is null or ta.expires_at>now())) count
     from public.addon_definitions a left join public.tenant_addons ta on ta.addon_id=a.id where a.is_active group by a.id) x)
 ) into result; return result; end $function$;

create or replace function public.platform_get_settings()
returns table(trial_duration_days integer,grace_period_days integer,default_billing_cycle text,default_currency text,
 support_email text,support_phone text,maintenance_mode boolean,maintenance_message text,updated_at timestamptz,updated_by uuid)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query select s.trial_duration_days,s.grace_period_days,s.default_billing_cycle,s.default_currency,
 s.support_email,s.support_phone,s.maintenance_mode,s.maintenance_message,s.updated_at,s.updated_by from public.platform_settings s where singleton; end $function$;

create or replace function public.platform_update_settings(p_trial_duration_days integer,p_grace_period_days integer,
 p_default_billing_cycle text,p_default_currency text,p_support_email text,p_support_phone text,p_maintenance_mode boolean,p_maintenance_message text)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare actor uuid; old_value jsonb; new_value jsonb; begin actor:=public.require_active_platform_admin();
 if p_trial_duration_days not between 0 and 365 or p_grace_period_days not between 0 and 90 or lower(trim(p_default_billing_cycle)) not in ('monthly','annual')
 or upper(trim(p_default_currency)) !~ '^[A-Z]{3}$' then raise exception using errcode='22023',message='Invalid platform settings.'; end if;
 select to_jsonb(s)-'updated_at'-'updated_by' into old_value from public.platform_settings s where singleton for update;
 update public.platform_settings set trial_duration_days=p_trial_duration_days,grace_period_days=p_grace_period_days,
 default_billing_cycle=lower(trim(p_default_billing_cycle)),default_currency=upper(trim(p_default_currency)),support_email=nullif(trim(p_support_email),''),
 support_phone=nullif(trim(p_support_phone),''),maintenance_mode=p_maintenance_mode,maintenance_message=nullif(trim(p_maintenance_message),''),updated_at=now(),updated_by=actor where singleton;
 select to_jsonb(s)-'updated_at'-'updated_by' into new_value from public.platform_settings s where singleton;
 if old_value is distinct from new_value then insert into public.entitlement_audit_logs(actor_admin_user_id,action,entity_type,reason,previous_value,new_value)
 values(actor,'platform.settings_updated','platform_settings','Global defaults updated',old_value,new_value); end if; end $function$;

revoke all on function public.platform_get_analytics(),public.platform_get_settings(),public.platform_update_settings(integer,integer,text,text,text,text,boolean,text) from public,anon;
grant execute on function public.platform_get_analytics(),public.platform_get_settings(),public.platform_update_settings(integer,integer,text,text,text,text,boolean,text) to authenticated,service_role;
