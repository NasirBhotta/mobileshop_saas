-- Admin Portal Patch 5: manual billing, payments, trials and renewals.

alter table public.tenant_subscriptions
  add column billing_cycle text not null default 'monthly'
    check (billing_cycle in ('monthly', 'annual')),
  add column trial_starts_at timestamptz,
  add column trial_ends_at timestamptz,
  add column renews_at timestamptz,
  add column grace_ends_at timestamptz,
  add constraint tenant_subscription_trial_dates_check
    check (trial_ends_at is null or trial_starts_at is null or trial_ends_at > trial_starts_at),
  add constraint tenant_subscription_grace_date_check
    check (grace_ends_at is null or grace_ends_at > starts_at);

create table public.billing_invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  subscription_id uuid references public.tenant_subscriptions(id) on delete restrict,
  invoice_number text not null check (length(trim(invoice_number)) > 0),
  amount numeric(14,2) not null check (amount >= 0),
  currency text not null default 'PKR' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'open' check (status in ('open', 'paid', 'void')),
  issued_at timestamptz not null default now(),
  due_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  constraint billing_invoice_due_check check (due_at is null or due_at >= issued_at),
  constraint billing_invoice_number_unique unique (invoice_number)
);
create index billing_invoices_tenant_created_idx on public.billing_invoices (tenant_id, created_at desc);

create table public.billing_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  invoice_id uuid references public.billing_invoices(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'PKR' check (currency ~ '^[A-Z]{3}$'),
  method text not null check (length(trim(method)) > 0),
  external_reference text not null check (length(trim(external_reference)) > 0),
  status text not null default 'recorded' check (status in ('recorded', 'verified', 'rejected')),
  paid_at timestamptz not null,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  verified_by uuid references auth.users(id) on delete restrict,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  constraint billing_payment_reference_unique unique (tenant_id, external_reference),
  constraint billing_payment_verification_check check (
    (status = 'recorded' and verified_by is null and verified_at is null)
    or (status in ('verified', 'rejected') and verified_by is not null and verified_at is not null)
  )
);
create index billing_payments_tenant_created_idx on public.billing_payments (tenant_id, created_at desc);

alter table public.billing_invoices enable row level security;
alter table public.billing_payments enable row level security;
revoke all on public.billing_invoices, public.billing_payments from anon, authenticated;
grant all on public.billing_invoices, public.billing_payments to service_role;

create or replace function public.prevent_billing_payment_mutation()
returns trigger language plpgsql set search_path = public, pg_temp as $function$
begin
  if old.status <> 'recorded' or new.status not in ('verified', 'rejected')
     or new.id <> old.id or new.tenant_id <> old.tenant_id
     or new.amount <> old.amount or new.currency <> old.currency
     or new.method <> old.method or new.external_reference <> old.external_reference
     or new.paid_at <> old.paid_at or new.recorded_by <> old.recorded_by
     or new.created_at <> old.created_at or new.invoice_id is distinct from old.invoice_id then
    raise exception using errcode = '42501', message = 'Payment history is immutable; only verification is allowed.';
  end if;
  return new;
end $function$;
create trigger billing_payments_immutable before update on public.billing_payments
for each row execute function public.prevent_billing_payment_mutation();
create trigger billing_payments_no_delete before delete on public.billing_payments
for each row execute function public.prevent_billing_payment_mutation();

create or replace function public.platform_get_billing_summary(p_tenant_id uuid)
returns table (subscription_id uuid, plan text, subscription_status text, billing_cycle text,
 trial_starts_at timestamptz, trial_ends_at timestamptz, renewal_date timestamptz,
 grace_ends_at timestamptz, outstanding_amount numeric, currency text)
language plpgsql stable security definer set search_path = public, pg_temp as $function$
begin
  perform public.require_active_platform_admin();
  return query select s.id, p.name, s.status, s.billing_cycle, s.trial_starts_at,
    s.trial_ends_at, s.renews_at, s.grace_ends_at,
    coalesce(sum(i.amount) filter (where i.status = 'open'), 0)::numeric, 'PKR'::text
  from public.tenant_subscriptions s join public.plans p on p.id = s.plan_id
  left join public.billing_invoices i on i.subscription_id = s.id
  where s.tenant_id = p_tenant_id and s.is_active and s.deleted_at is null
  group by s.id, p.name;
end $function$;

create or replace function public.platform_list_billing_invoices(p_tenant_id uuid)
returns setof public.billing_invoices language plpgsql stable security definer
set search_path = public, pg_temp as $function$
begin perform public.require_active_platform_admin();
 return query select * from public.billing_invoices where tenant_id=p_tenant_id order by issued_at desc;
end $function$;
create or replace function public.platform_list_billing_payments(p_tenant_id uuid)
returns setof public.billing_payments language plpgsql stable security definer
set search_path = public, pg_temp as $function$
begin perform public.require_active_platform_admin();
 return query select * from public.billing_payments where tenant_id=p_tenant_id order by paid_at desc;
end $function$;

create or replace function public.platform_record_manual_payment(p_tenant_id uuid, p_invoice_id uuid,
 p_amount numeric, p_currency text, p_method text, p_external_reference text, p_paid_at timestamptz)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $function$
declare actor uuid; payment_id uuid; invoice_tenant uuid;
begin
 actor := public.require_active_platform_admin();
 if p_amount <= 0 or nullif(trim(p_method),'') is null or nullif(trim(p_external_reference),'') is null then
   raise exception using errcode='22023', message='Valid payment details are required.'; end if;
 if p_invoice_id is not null then select tenant_id into invoice_tenant from public.billing_invoices where id=p_invoice_id;
   if invoice_tenant is distinct from p_tenant_id then raise exception using errcode='22023', message='Invoice does not belong to tenant.'; end if; end if;
 insert into public.billing_payments(tenant_id,invoice_id,amount,currency,method,external_reference,paid_at,recorded_by)
 values(p_tenant_id,p_invoice_id,p_amount,upper(trim(p_currency)),trim(p_method),trim(p_external_reference),p_paid_at,actor)
 returning id into payment_id;
 insert into public.entitlement_audit_logs(tenant_id,action,entity_type,entity_id,reason,new_value)
 values(p_tenant_id,'billing.payment_recorded','billing_payment',payment_id,'Manual payment recorded',
 jsonb_build_object('amount',p_amount,'currency',upper(trim(p_currency)),'reference',trim(p_external_reference)));
 return payment_id;
exception when unique_violation then raise exception using errcode='23505', message='This payment reference has already been recorded.';
end $function$;

create or replace function public.platform_verify_manual_payment(p_payment_id uuid, p_verified boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $function$
declare actor uuid; pay public.billing_payments%rowtype;
begin
 actor:=public.require_active_platform_admin(); select * into pay from public.billing_payments where id=p_payment_id for update;
 if pay.id is null then raise exception using errcode='P0002',message='Payment not found.'; end if;
 if pay.status <> 'recorded' then raise exception using errcode='22023',message='Payment has already been reviewed.'; end if;
 update public.billing_payments set status=case when p_verified then 'verified' else 'rejected' end,
 verified_by=actor,verified_at=now() where id=p_payment_id;
 if p_verified and pay.invoice_id is not null then update public.billing_invoices set status='paid',paid_at=pay.paid_at where id=pay.invoice_id and status='open'; end if;
 insert into public.entitlement_audit_logs(tenant_id,action,entity_type,entity_id,reason,previous_value,new_value)
 values(pay.tenant_id,case when p_verified then 'billing.payment_verified' else 'billing.payment_rejected' end,
 'billing_payment',pay.id,nullif(trim(p_reason),''),jsonb_build_object('status','recorded'),
 jsonb_build_object('status',case when p_verified then 'verified' else 'rejected' end));
end $function$;

create or replace function public.platform_manage_subscription(p_tenant_id uuid,p_action text,p_effective_at timestamptz default now(),
 p_until timestamptz default null,p_billing_cycle text default null,p_reason text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $function$
declare actor uuid; s public.tenant_subscriptions%rowtype; action text:=lower(trim(p_action)); next_status text;
begin
 actor:=public.require_active_platform_admin(); select * into s from public.tenant_subscriptions
 where tenant_id=p_tenant_id and is_active and deleted_at is null for update;
 if s.id is null then raise exception using errcode='P0002',message='Active subscription not found.'; end if;
 if action not in ('trial_start','trial_extend','trial_end','activate','cancel','renew','suspend','grace') then
  raise exception using errcode='22023',message='Unsupported subscription action.'; end if;
 if action in ('trial_start','trial_extend','grace','renew') and p_until is null then raise exception using errcode='22023',message='An end or renewal date is required.'; end if;
 next_status:=case when action in ('trial_start','trial_extend') then 'trialing' when action in ('trial_end','activate','renew') then 'active'
  when action='cancel' then 'cancelled' when action='suspend' then 'suspended' when action='grace' then 'grace_period' end;
 update public.tenant_subscriptions set status=next_status,
  billing_cycle=coalesce(nullif(trim(p_billing_cycle),''),billing_cycle),
  trial_starts_at=case when action='trial_start' then p_effective_at else trial_starts_at end,
  trial_ends_at=case when action in ('trial_start','trial_extend') then p_until when action='trial_end' then p_effective_at else trial_ends_at end,
  renews_at=case when action='renew' then p_until else renews_at end,
  grace_ends_at=case when action='grace' then p_until when action in ('activate','renew','cancel','suspend') then null else grace_ends_at end,
  expires_at=case when action='cancel' then p_effective_at when action in ('activate','renew') then p_until else expires_at end,
  reason=nullif(trim(p_reason),'') where id=s.id;
 update public.tenants set status=case when action='suspend' then 'suspended' when action in ('activate','renew') then 'active' else status end where id=p_tenant_id;
 insert into public.entitlement_audit_logs(tenant_id,action,entity_type,entity_id,reason,previous_value,new_value)
 values(p_tenant_id,'billing.subscription_'||action,'tenant_subscription',s.id,nullif(trim(p_reason),''),
 jsonb_build_object('status',s.status),jsonb_build_object('status',next_status,'until',p_until,'billing_cycle',coalesce(p_billing_cycle,s.billing_cycle)));
end $function$;

revoke all on function public.platform_get_billing_summary(uuid), public.platform_list_billing_invoices(uuid),
 public.platform_list_billing_payments(uuid), public.platform_record_manual_payment(uuid,uuid,numeric,text,text,text,timestamptz),
 public.platform_verify_manual_payment(uuid,boolean,text), public.platform_manage_subscription(uuid,text,timestamptz,timestamptz,text,text) from public,anon;
grant execute on function public.platform_get_billing_summary(uuid), public.platform_list_billing_invoices(uuid),
 public.platform_list_billing_payments(uuid), public.platform_record_manual_payment(uuid,uuid,numeric,text,text,text,timestamptz),
 public.platform_verify_manual_payment(uuid,boolean,text), public.platform_manage_subscription(uuid,text,timestamptz,timestamptz,text,text) to authenticated,service_role;
