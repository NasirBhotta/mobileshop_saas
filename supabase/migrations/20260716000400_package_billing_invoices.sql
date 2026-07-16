-- Package-specific manual billing invoice foundation. Payment verification and
-- subscription activation remain separate until the next billing patch.

alter table public.billing_invoices
  add column plan_id uuid references public.plans(id) on delete restrict,
  add column plan_key_snapshot text,
  add column plan_name_snapshot text,
  add column billing_cycle text check (billing_cycle in ('monthly', 'annual')),
  add column original_amount numeric(14,2) check (original_amount is null or original_amount >= 0),
  add column discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  add column service_months integer check (service_months is null or service_months > 0),
  add column note text;

alter table public.billing_invoices
  add constraint billing_invoice_amount_breakdown_check check (
    original_amount is null
    or amount = original_amount - discount_amount
  );

create index billing_invoices_plan_idx
on public.billing_invoices(plan_id, created_at desc);

create or replace function public.platform_create_package_invoice(
  p_tenant_id uuid,
  p_plan_id uuid,
  p_billing_cycle text,
  p_original_amount numeric,
  p_discount_amount numeric default 0,
  p_due_at timestamptz default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  selected_plan public.plans%rowtype;
  subscription_id uuid;
  invoice_id uuid := gen_random_uuid();
  normalized_cycle text := lower(trim(p_billing_cycle));
  normalized_discount numeric := coalesce(p_discount_amount, 0);
  final_amount numeric;
begin
  perform public.require_active_platform_admin();

  if not exists (select 1 from public.tenants where id = p_tenant_id) then
    raise exception using errcode = 'P0002', message = 'Tenant not found.';
  end if;

  select * into selected_plan
  from public.plans
  where id = p_plan_id and is_active and deleted_at is null;
  if selected_plan.id is null then
    raise exception using errcode = 'P0002', message = 'Active package not found.';
  end if;

  if normalized_cycle not in ('monthly', 'annual') then
    raise exception using errcode = '22023', message = 'Billing cycle must be monthly or annual.';
  end if;
  if p_original_amount is null or p_original_amount <= 0 then
    raise exception using errcode = '22023', message = 'Invoice amount must be greater than zero.';
  end if;
  if normalized_discount < 0 or normalized_discount >= p_original_amount then
    raise exception using errcode = '22023', message = 'Discount must be non-negative and less than the original amount.';
  end if;
  if p_due_at is not null and p_due_at < now() then
    raise exception using errcode = '22023', message = 'Invoice due date cannot be in the past.';
  end if;

  final_amount := p_original_amount - normalized_discount;
  select s.id into subscription_id
  from public.tenant_subscriptions s
  where s.tenant_id = p_tenant_id and s.is_active and s.deleted_at is null;

  insert into public.billing_invoices (
    id, tenant_id, subscription_id, invoice_number, amount, currency,
    status, issued_at, due_at, plan_id, plan_key_snapshot,
    plan_name_snapshot, billing_cycle, original_amount, discount_amount,
    service_months, note
  ) values (
    invoice_id, p_tenant_id, subscription_id,
    'INV-' || to_char(now(), 'YYYYMM') || '-' || upper(substr(replace(invoice_id::text, '-', ''), 1, 8)),
    final_amount, 'PKR', 'open', now(), p_due_at, selected_plan.id,
    selected_plan.key, selected_plan.name, normalized_cycle,
    p_original_amount, normalized_discount,
    case when normalized_cycle = 'annual' then 12 else 1 end,
    nullif(trim(p_note), '')
  );

  insert into public.entitlement_audit_logs (
    tenant_id, action, entity_type, entity_id, reason, new_value
  ) values (
    p_tenant_id, 'billing.invoice_created', 'billing_invoice', invoice_id,
    nullif(trim(p_note), ''),
    jsonb_build_object(
      'plan_id', selected_plan.id,
      'plan_key', selected_plan.key,
      'billing_cycle', normalized_cycle,
      'original_amount', p_original_amount,
      'discount_amount', normalized_discount,
      'amount', final_amount,
      'due_at', p_due_at
    )
  );

  return invoice_id;
end
$function$;

revoke all on function public.platform_create_package_invoice(
  uuid, uuid, text, numeric, numeric, timestamptz, text
) from public, anon;
grant execute on function public.platform_create_package_invoice(
  uuid, uuid, text, numeric, numeric, timestamptz, text
) to authenticated, service_role;
