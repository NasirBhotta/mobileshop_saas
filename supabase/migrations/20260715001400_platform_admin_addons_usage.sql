-- Admin Portal Patch 6: add-on catalog, tenant assignments and usage visibility.

create table public.addon_definitions (
  id uuid primary key default gen_random_uuid(),
  key text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  name text not null check (length(trim(name)) > 0),
  description text,
  price numeric(14,2) not null default 0 check (price >= 0),
  billing_type text not null default 'monthly'
    check (billing_type in ('one_time', 'monthly', 'annual', 'per_unit')),
  feature_id uuid references public.features(id) on delete restrict,
  limit_key text check (limit_key is null or limit_key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  limit_increase numeric check (limit_increase is null or limit_increase > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint addon_definitions_key_unique unique (key),
  constraint addon_limit_pair_check check ((limit_key is null) = (limit_increase is null))
);
create trigger addon_definitions_updated_at before update on public.addon_definitions
for each row execute function public.set_updated_at();

alter table public.tenant_addons
  add column addon_id uuid references public.addon_definitions(id) on delete restrict,
  add column quantity integer not null default 1 check (quantity > 0),
  add column starts_at timestamptz not null default now(),
  add column expires_at timestamptz,
  add column status text not null default 'active' check (status in ('scheduled','active','expired','removed')),
  add column updated_at timestamptz not null default now(),
  add constraint tenant_addons_dates_check check (expires_at is null or expires_at > starts_at);
create unique index tenant_addons_definition_unique on public.tenant_addons (tenant_id, addon_id) where addon_id is not null;
create trigger tenant_addons_updated_at before update on public.tenant_addons
for each row execute function public.set_updated_at();

create table public.tenant_usage_metrics (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  limit_key text not null check (limit_key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  used_value numeric not null check (used_value >= 0),
  measured_at timestamptz not null default now(),
  primary key (tenant_id, limit_key)
);

alter table public.addon_definitions enable row level security;
alter table public.tenant_usage_metrics enable row level security;
revoke all on public.addon_definitions, public.tenant_usage_metrics from anon, authenticated;
grant all on public.addon_definitions, public.tenant_usage_metrics to service_role;

create or replace function public.platform_list_addons()
returns table(id uuid,key text,name text,description text,price numeric,billing_type text,
 feature_id uuid,feature_key text,limit_key text,limit_increase numeric,is_active boolean,assigned_tenants bigint)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query
 select a.id,a.key,a.name,a.description,a.price,a.billing_type,a.feature_id,f.key,a.limit_key,a.limit_increase,a.is_active,
 count(ta.id) filter(where ta.status in ('scheduled','active'))
 from public.addon_definitions a left join public.features f on f.id=a.feature_id
 left join public.tenant_addons ta on ta.addon_id=a.id group by a.id,f.key order by a.name; end $function$;

create or replace function public.platform_save_addon(p_id uuid,p_key text,p_name text,p_description text,
 p_price numeric,p_billing_type text,p_feature_id uuid,p_limit_key text,p_limit_increase numeric,p_is_active boolean default true)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $function$
declare result uuid; old jsonb;
begin perform public.require_active_platform_admin();
 if p_price<0 or lower(trim(p_billing_type)) not in ('one_time','monthly','annual','per_unit') then raise exception using errcode='22023',message='Invalid add-on price or billing type.'; end if;
 if (p_limit_key is null)<>(p_limit_increase is null) then raise exception using errcode='22023',message='Limit key and increase must be supplied together.'; end if;
 if p_id is null then
  insert into public.addon_definitions(key,name,description,price,billing_type,feature_id,limit_key,limit_increase,is_active)
  values(lower(trim(p_key)),trim(p_name),nullif(trim(p_description),''),p_price,lower(trim(p_billing_type)),p_feature_id,nullif(trim(p_limit_key),''),p_limit_increase,p_is_active) returning id into result;
 else
  select to_jsonb(a) into old from public.addon_definitions a where id=p_id for update;
  if old is null then raise exception using errcode='P0002',message='Add-on not found.'; end if;
  update public.addon_definitions set key=lower(trim(p_key)),name=trim(p_name),description=nullif(trim(p_description),''),price=p_price,
   billing_type=lower(trim(p_billing_type)),feature_id=p_feature_id,limit_key=nullif(trim(p_limit_key),''),limit_increase=p_limit_increase,is_active=p_is_active where id=p_id returning id into result;
 end if;
 insert into public.entitlement_audit_logs(action,entity_type,entity_id,previous_value,new_value)
 values(case when p_id is null then 'addon.created' else 'addon.updated' end,'addon_definition',result,old,(select to_jsonb(a) from public.addon_definitions a where id=result)); return result;
end $function$;

create or replace function public.platform_deactivate_addon(p_addon_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare old_active boolean; begin perform public.require_active_platform_admin(); select is_active into old_active from public.addon_definitions where id=p_addon_id for update;
 if old_active is null then raise exception using errcode='P0002',message='Add-on not found.'; end if;
 update public.addon_definitions set is_active=false where id=p_addon_id;
 insert into public.entitlement_audit_logs(action,entity_type,entity_id,reason,previous_value,new_value)
 values('addon.deactivated','addon_definition',p_addon_id,nullif(trim(p_reason),''),jsonb_build_object('is_active',old_active),jsonb_build_object('is_active',false)); end $function$;

create or replace function public.platform_list_tenant_addons(p_tenant_id uuid)
returns table(assignment_id uuid,addon_id uuid,addon_key text,addon_name text,price numeric,billing_type text,
 quantity integer,starts_at timestamptz,expires_at timestamptz,status text,feature_key text,limit_key text,limit_increase numeric)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query select ta.id,a.id,a.key,a.name,a.price,a.billing_type,ta.quantity,ta.starts_at,
 ta.expires_at,ta.status,f.key,a.limit_key,a.limit_increase from public.tenant_addons ta join public.addon_definitions a on a.id=ta.addon_id
 left join public.features f on f.id=a.feature_id where ta.tenant_id=p_tenant_id order by ta.created_at desc; end $function$;

create or replace function public.platform_assign_tenant_addon(p_tenant_id uuid,p_addon_id uuid,p_quantity integer default 1,
 p_starts_at timestamptz default now(),p_expires_at timestamptz default null,p_status text default 'active',p_reason text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $function$
declare result uuid; addon_key_value text; old jsonb; begin perform public.require_active_platform_admin();
 if p_quantity<1 or p_status not in ('scheduled','active','expired') or (p_expires_at is not null and p_expires_at<=p_starts_at) then raise exception using errcode='22023',message='Invalid add-on assignment.'; end if;
 select key into addon_key_value from public.addon_definitions where id=p_addon_id and is_active; if addon_key_value is null then raise exception using errcode='22023',message='Active add-on not found.'; end if;
 select to_jsonb(ta) into old from public.tenant_addons ta where tenant_id=p_tenant_id and addon_id=p_addon_id for update;
 insert into public.tenant_addons(tenant_id,addon_key,addon_id,enabled,quantity,starts_at,expires_at,status)
 values(p_tenant_id,addon_key_value,p_addon_id,p_status='active',p_quantity,p_starts_at,p_expires_at,p_status)
 on conflict(tenant_id,addon_id) where addon_id is not null do update set enabled=excluded.enabled,quantity=excluded.quantity,starts_at=excluded.starts_at,expires_at=excluded.expires_at,status=excluded.status
 returning id into result;
 insert into public.entitlement_audit_logs(tenant_id,action,entity_type,entity_id,reason,previous_value,new_value)
 values(p_tenant_id,case when old is null then 'addon.assigned' else 'addon.assignment_updated' end,'tenant_addon',result,nullif(trim(p_reason),''),old,(select to_jsonb(ta) from public.tenant_addons ta where id=result)); return result; end $function$;

create or replace function public.platform_remove_tenant_addon(p_assignment_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare row_before public.tenant_addons%rowtype; begin perform public.require_active_platform_admin(); select * into row_before from public.tenant_addons where id=p_assignment_id for update;
 if row_before.id is null then raise exception using errcode='P0002',message='Assignment not found.'; end if;
 update public.tenant_addons
 set enabled=false,
     status='removed',
     expires_at=case
       when expires_at is null or expires_at>clock_timestamp()
         then greatest(clock_timestamp(), starts_at + interval '1 microsecond')
       else expires_at
     end
 where id=p_assignment_id;
 insert into public.entitlement_audit_logs(tenant_id,action,entity_type,entity_id,reason,previous_value,new_value)
 values(row_before.tenant_id,'addon.removed','tenant_addon',row_before.id,nullif(trim(p_reason),''),to_jsonb(row_before),jsonb_build_object('status','removed')); end $function$;

create or replace function public.platform_get_tenant_usage(p_tenant_id uuid)
returns table(limit_key text,used_value numeric,plan_limit numeric,override_limit numeric,addon_increase numeric,effective_limit numeric,usage_percent numeric,warning_level text,measured_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query
 with sub as(select plan_id from public.tenant_subscriptions where tenant_id=p_tenant_id and is_active and deleted_at is null limit 1),
 additions as(select a.limit_key,sum(a.limit_increase*ta.quantity) increase from public.tenant_addons ta join public.addon_definitions a on a.id=ta.addon_id
  where ta.tenant_id=p_tenant_id and ta.enabled and ta.status='active' and ta.starts_at<=now() and (ta.expires_at is null or ta.expires_at>now()) and a.is_active and a.limit_key is not null group by a.limit_key),
 valueset as(select u.*,pl.value plan_value,o.value override_value,coalesce(ad.increase,0) increase from public.tenant_usage_metrics u left join sub on true
  left join public.plan_limits pl on pl.plan_id=sub.plan_id and pl.key=u.limit_key and pl.is_active and pl.deleted_at is null
  left join public.tenant_limit_overrides o on o.tenant_id=p_tenant_id and o.key=u.limit_key and o.is_active and o.deleted_at is null and (o.expires_at is null or o.expires_at>now())
  left join additions ad on ad.limit_key=u.limit_key where u.tenant_id=p_tenant_id)
 select v.limit_key,v.used_value,v.plan_value,v.override_value,v.increase,
 case when coalesce(v.override_value,v.plan_value)=-1 then -1 else coalesce(v.override_value,v.plan_value,0)+v.increase end effective,
 case when coalesce(v.override_value,v.plan_value)=-1 then 0 when coalesce(v.override_value,v.plan_value,0)+v.increase=0 then 100
  else round(v.used_value*100/(coalesce(v.override_value,v.plan_value,0)+v.increase),2) end,
 case when coalesce(v.override_value,v.plan_value)=-1 then 'ok' when v.used_value>coalesce(v.override_value,v.plan_value,0)+v.increase then 'exceeded'
  when v.used_value>=.8*(coalesce(v.override_value,v.plan_value,0)+v.increase) then 'approaching' else 'ok' end,v.measured_at from valueset v order by v.limit_key; end $function$;

do $grants$ declare s text; begin foreach s in array array['public.platform_list_addons()','public.platform_save_addon(uuid,text,text,text,numeric,text,uuid,text,numeric,boolean)',
'public.platform_deactivate_addon(uuid,text)','public.platform_list_tenant_addons(uuid)','public.platform_assign_tenant_addon(uuid,uuid,integer,timestamptz,timestamptz,text,text)',
'public.platform_remove_tenant_addon(uuid,text)','public.platform_get_tenant_usage(uuid)'] loop execute format('revoke all on function %s from public,anon',s); execute format('grant execute on function %s to authenticated,service_role',s); end loop; end $grants$;
