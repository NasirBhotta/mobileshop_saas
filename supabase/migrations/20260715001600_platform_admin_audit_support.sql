-- Admin Portal Patch 7: safe audit, diagnostics and account support tools.

alter table public.entitlement_audit_logs
  add column actor_admin_user_id uuid references auth.users(id) on delete set null;
create index entitlement_audit_admin_created_idx
on public.entitlement_audit_logs (actor_admin_user_id, created_at desc);

create table public.offline_mutation_failures (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
  mutation_type text not null check (length(trim(mutation_type)) > 0),
  diagnostic_code text,
  status text not null default 'failed' check (status in ('failed','retry_requested','resolved')),
  attempt_count integer not null default 1 check (attempt_count >= 1),
  failed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  -- No mutation payload or customer data is stored in this support table.
  constraint offline_failure_resolution_check check (status='resolved' or resolved_at is null)
);
create trigger offline_mutation_failures_updated_at before update on public.offline_mutation_failures
for each row execute function public.set_updated_at();

create table public.platform_support_notes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  subject_user_id uuid references auth.users(id) on delete set null,
  category text not null check (category in ('account_recovery','support')),
  note text not null check (length(trim(note)) between 1 and 2000),
  status text not null default 'open' check (status in ('open','resolved')),
  created_by uuid not null references auth.users(id) on delete restrict,
  resolved_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint support_note_resolution_check check (
    (status='open' and resolved_by is null and resolved_at is null)
    or (status='resolved' and resolved_by is not null and resolved_at is not null)
  )
);

alter table public.offline_mutation_failures enable row level security;
alter table public.platform_support_notes enable row level security;
revoke all on public.offline_mutation_failures, public.platform_support_notes from anon,authenticated;
grant all on public.offline_mutation_failures, public.platform_support_notes to service_role;

create or replace function public.platform_list_audit_logs(p_tenant_id uuid default null,p_action text default null,
 p_admin_user_id uuid default null,p_from timestamptz default null,p_to timestamptz default null,p_limit integer default 200)
returns table(id uuid,tenant_id uuid,tenant_name text,admin_user_id uuid,action text,entity_type text,entity_id uuid,reason text,created_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query
 select l.id,l.tenant_id,t.shop_name,coalesce(l.actor_admin_user_id,l.actor_user_id),l.action,l.entity_type,l.entity_id,l.reason,l.created_at
 from public.entitlement_audit_logs l left join public.tenants t on t.id=l.tenant_id
 where (p_tenant_id is null or l.tenant_id=p_tenant_id) and (nullif(trim(p_action),'') is null or l.action ilike '%'||trim(p_action)||'%')
 and (p_admin_user_id is null or coalesce(l.actor_admin_user_id,l.actor_user_id)=p_admin_user_id)
 and (p_from is null or l.created_at>=p_from) and (p_to is null or l.created_at<p_to)
 order by l.created_at desc limit least(greatest(p_limit,1),500); end $function$;

create or replace function public.platform_tenant_activity(p_tenant_id uuid,p_limit integer default 100)
returns table(id uuid,action text,entity_type text,entity_id uuid,admin_user_id uuid,reason text,created_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query select l.id,l.action,l.entity_type,l.entity_id,
 coalesce(l.actor_admin_user_id,l.actor_user_id),l.reason,l.created_at from public.entitlement_audit_logs l where l.tenant_id=p_tenant_id
 order by l.created_at desc limit least(greatest(p_limit,1),500); end $function$;

create or replace function public.platform_list_failed_report_jobs()
returns table(job_type text,job_id uuid,tenant_id uuid,schedule_id uuid,status text,error_code text,created_at timestamptz,processed_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query
 select 'sales'::text,j.id,j.tenant_id,j.schedule_id,j.status,
   case when nullif(trim(j.error_message),'') is null then null else 'REPORT_DELIVERY_FAILED' end,j.created_at,j.processed_at
 from public.sales_report_delivery_jobs j where j.status='failed'
 union all
 select 'business'::text,j.id,j.tenant_id,j.schedule_id,j.status,
   case when nullif(trim(j.error_message),'') is null then null else 'REPORT_DELIVERY_FAILED' end,j.created_at,j.processed_at
 from public.business_report_delivery_jobs j where j.status='failed'
 order by created_at desc; end $function$;

create or replace function public.platform_retry_report_job(p_job_type text,p_job_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare actor uuid; affected integer; tenant uuid; begin actor:=public.require_active_platform_admin();
 if p_job_type='sales' then update public.sales_report_delivery_jobs set status='pending',error_message=null,processed_at=null where id=p_job_id and status='failed' returning tenant_id into tenant;
 elsif p_job_type='business' then update public.business_report_delivery_jobs set status='pending',error_message=null,processed_at=null where id=p_job_id and status='failed' returning tenant_id into tenant;
 else raise exception using errcode='22023',message='Unsupported report job type.'; end if;
 get diagnostics affected=row_count; if affected=0 then raise exception using errcode='P0002',message='Failed report job not found.'; end if;
 insert into public.entitlement_audit_logs(tenant_id,actor_admin_user_id,action,entity_type,entity_id,new_value)
 values(tenant,actor,'support.report_job_retry_requested','report_job',p_job_id,jsonb_build_object('job_type',p_job_type,'status','pending')); end $function$;

create or replace function public.platform_list_failed_offline_mutations()
returns table(id uuid,tenant_id uuid,user_id uuid,mutation_type text,diagnostic_code text,status text,attempt_count integer,failed_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query select f.id,f.tenant_id,f.user_id,f.mutation_type,f.diagnostic_code,f.status,f.attempt_count,f.failed_at
 from public.offline_mutation_failures f where f.status in ('failed','retry_requested') order by f.failed_at desc; end $function$;

create or replace function public.platform_update_offline_failure(p_id uuid,p_action text,p_reason text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare actor uuid; row_before public.offline_mutation_failures%rowtype; next_status text; begin actor:=public.require_active_platform_admin();
 select * into row_before from public.offline_mutation_failures where id=p_id for update; if row_before.id is null then raise exception using errcode='P0002',message='Offline failure not found.'; end if;
 next_status:=case p_action when 'retry' then 'retry_requested' when 'resolve' then 'resolved' else null end;
 if next_status is null then raise exception using errcode='22023',message='Action must be retry or resolve.'; end if;
 update public.offline_mutation_failures set status=next_status,resolved_at=case when next_status='resolved' then now() else null end where id=p_id;
 insert into public.entitlement_audit_logs(tenant_id,actor_admin_user_id,action,entity_type,entity_id,reason,previous_value,new_value)
 values(row_before.tenant_id,actor,'support.offline_mutation_'||p_action,'offline_mutation_failure',p_id,nullif(trim(p_reason),''),jsonb_build_object('status',row_before.status),jsonb_build_object('status',next_status)); end $function$;

create or replace function public.platform_list_support_notes(p_tenant_id uuid)
returns table(id uuid,subject_user_id uuid,category text,note text,status text,created_by uuid,created_at timestamptz,resolved_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin perform public.require_active_platform_admin(); return query select n.id,n.subject_user_id,n.category,n.note,n.status,n.created_by,n.created_at,n.resolved_at
 from public.platform_support_notes n where n.tenant_id=p_tenant_id order by n.created_at desc; end $function$;

create or replace function public.platform_add_support_note(p_tenant_id uuid,p_subject_user_id uuid,p_category text,p_note text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $function$
declare actor uuid; result uuid; begin actor:=public.require_active_platform_admin();
 insert into public.platform_support_notes(tenant_id,subject_user_id,category,note,created_by) values(p_tenant_id,p_subject_user_id,p_category,trim(p_note),actor) returning id into result;
 insert into public.entitlement_audit_logs(tenant_id,actor_admin_user_id,action,entity_type,entity_id,new_value)
 values(p_tenant_id,actor,'support.note_added','support_note',result,jsonb_build_object('category',p_category,'subject_user_id',p_subject_user_id)); return result; end $function$;

create or replace function public.platform_resolve_support_note(p_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare actor uuid; tenant uuid; begin actor:=public.require_active_platform_admin(); update public.platform_support_notes set status='resolved',resolved_by=actor,resolved_at=now()
 where id=p_id and status='open' returning tenant_id into tenant; if tenant is null then raise exception using errcode='P0002',message='Open support note not found.'; end if;
 insert into public.entitlement_audit_logs(tenant_id,actor_admin_user_id,action,entity_type,entity_id,new_value)
 values(tenant,actor,'support.note_resolved','support_note',p_id,jsonb_build_object('status','resolved')); end $function$;

do $grants$ declare s text; begin foreach s in array array['public.platform_list_audit_logs(uuid,text,uuid,timestamptz,timestamptz,integer)','public.platform_tenant_activity(uuid,integer)',
'public.platform_list_failed_report_jobs()','public.platform_retry_report_job(text,uuid)','public.platform_list_failed_offline_mutations()',
'public.platform_update_offline_failure(uuid,text,text)','public.platform_list_support_notes(uuid)','public.platform_add_support_note(uuid,uuid,text,text)','public.platform_resolve_support_note(uuid)']
loop execute format('revoke all on function %s from public,anon',s); execute format('grant execute on function %s to authenticated,service_role',s); end loop; end $grants$;
