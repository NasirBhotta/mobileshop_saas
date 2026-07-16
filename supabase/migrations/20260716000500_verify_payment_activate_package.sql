-- Require invoice-linked manual payments and atomically activate the invoiced
-- package only after platform-admin verification.

create or replace function public.prevent_multiple_open_billing_invoices()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $function$
begin
  if new.status = 'open' and exists (
    select 1 from public.billing_invoices i
    where i.tenant_id = new.tenant_id and i.status = 'open'
  ) then
    raise exception using errcode = '23505', message = 'Tenant already has an open invoice.';
  end if;
  return new;
end
$function$;

drop trigger if exists billing_invoices_one_open on public.billing_invoices;
create trigger billing_invoices_one_open
before insert on public.billing_invoices
for each row execute function public.prevent_multiple_open_billing_invoices();

create or replace function public.platform_void_billing_invoice(
  p_invoice_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  invoice public.billing_invoices%rowtype;
begin
  perform public.require_active_platform_admin();
  select * into invoice from public.billing_invoices
  where id = p_invoice_id for update;
  if invoice.id is null then
    raise exception using errcode = 'P0002', message = 'Invoice not found.';
  end if;
  if invoice.status <> 'open' then
    raise exception using errcode = '22023', message = 'Only an open invoice can be voided.';
  end if;
  if exists (
    select 1 from public.billing_payments p
    where p.invoice_id = invoice.id and p.status in ('recorded', 'verified')
  ) then
    raise exception using errcode = '22023', message = 'Review the linked payment before voiding this invoice.';
  end if;
  update public.billing_invoices set status = 'void' where id = invoice.id;
  insert into public.entitlement_audit_logs (
    tenant_id, action, entity_type, entity_id, reason,
    previous_value, new_value
  ) values (
    invoice.tenant_id, 'billing.invoice_voided', 'billing_invoice', invoice.id,
    nullif(trim(p_reason), ''), jsonb_build_object('status', 'open'),
    jsonb_build_object('status', 'void')
  );
end
$function$;

create or replace function public.platform_record_manual_payment(
  p_tenant_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_currency text,
  p_method text,
  p_external_reference text,
  p_paid_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor uuid;
  payment_id uuid;
  invoice public.billing_invoices%rowtype;
begin
  actor := public.require_active_platform_admin();
  if p_invoice_id is null then
    raise exception using errcode = '22023', message = 'An open package invoice is required.';
  end if;
  if nullif(trim(p_method), '') is null
     or nullif(trim(p_external_reference), '') is null
     or p_paid_at is null then
    raise exception using errcode = '22023', message = 'Valid payment details are required.';
  end if;

  select * into invoice
  from public.billing_invoices
  where id = p_invoice_id
  for update;

  if invoice.id is null or invoice.tenant_id <> p_tenant_id then
    raise exception using errcode = '22023', message = 'Invoice does not belong to tenant.';
  end if;
  if invoice.status <> 'open' then
    raise exception using errcode = '22023', message = 'Only an open invoice can receive payment.';
  end if;
  if invoice.plan_id is null or invoice.service_months is null then
    raise exception using errcode = '22023', message = 'A package-specific invoice is required.';
  end if;
  if p_amount is distinct from invoice.amount
     or upper(trim(p_currency)) <> invoice.currency then
    raise exception using errcode = '22023', message = 'Payment must exactly match the invoice payable amount and currency.';
  end if;
  if exists (
    select 1 from public.billing_payments bp
    where bp.invoice_id = invoice.id and bp.status in ('recorded', 'verified')
  ) then
    raise exception using errcode = '22023', message = 'This invoice already has a pending or verified payment.';
  end if;

  insert into public.billing_payments (
    tenant_id, invoice_id, amount, currency, method,
    external_reference, paid_at, recorded_by
  ) values (
    p_tenant_id, invoice.id, invoice.amount, invoice.currency,
    trim(p_method), trim(p_external_reference), p_paid_at, actor
  ) returning id into payment_id;

  insert into public.entitlement_audit_logs (
    tenant_id, action, entity_type, entity_id, reason, new_value
  ) values (
    p_tenant_id, 'billing.payment_recorded', 'billing_payment', payment_id,
    'Manual invoice payment recorded',
    jsonb_build_object(
      'invoice_id', invoice.id,
      'amount', invoice.amount,
      'currency', invoice.currency,
      'reference', trim(p_external_reference)
    )
  );
  return payment_id;
exception
  when unique_violation then
    raise exception using errcode = '23505', message = 'This payment reference has already been recorded.';
end
$function$;

create or replace function public.platform_verify_manual_payment(
  p_payment_id uuid,
  p_verified boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor uuid;
  pay public.billing_payments%rowtype;
  invoice public.billing_invoices%rowtype;
  subscription public.tenant_subscriptions%rowtype;
  verified_time timestamptz := now();
  service_end timestamptz;
begin
  actor := public.require_active_platform_admin();
  select * into pay
  from public.billing_payments
  where id = p_payment_id
  for update;

  if pay.id is null then
    raise exception using errcode = 'P0002', message = 'Payment not found.';
  end if;
  if pay.status <> 'recorded' then
    raise exception using errcode = '22023', message = 'Payment has already been reviewed.';
  end if;
  if pay.invoice_id is null then
    raise exception using errcode = '22023', message = 'Payment is not linked to an invoice.';
  end if;

  select * into invoice
  from public.billing_invoices
  where id = pay.invoice_id
  for update;
  if invoice.id is null or invoice.status <> 'open' then
    raise exception using errcode = '22023', message = 'Linked invoice is not open.';
  end if;

  if not p_verified then
    update public.billing_payments
    set status = 'rejected', verified_by = actor, verified_at = verified_time
    where id = pay.id;
  else
    if pay.amount <> invoice.amount or pay.currency <> invoice.currency then
      raise exception using errcode = '22023', message = 'Payment no longer matches the invoice.';
    end if;
    if invoice.plan_id is null or invoice.service_months is null then
      raise exception using errcode = '22023', message = 'Invoice package details are incomplete.';
    end if;

    select * into subscription
    from public.tenant_subscriptions
    where tenant_id = pay.tenant_id and is_active and deleted_at is null
    for update;
    if subscription.id is null then
      raise exception using errcode = 'P0002', message = 'Current subscription not found.';
    end if;

    service_end := verified_time + make_interval(months => invoice.service_months);

    update public.billing_payments
    set status = 'verified', verified_by = actor, verified_at = verified_time
    where id = pay.id;

    update public.billing_invoices
    set status = 'paid', paid_at = verified_time
    where id = invoice.id;

    update public.tenant_subscriptions
    set plan_id = invoice.plan_id,
        status = 'active',
        billing_cycle = invoice.billing_cycle,
        starts_at = verified_time,
        expires_at = service_end,
        renews_at = service_end,
        grace_ends_at = null,
        reason = 'Activated by verified invoice payment'
    where id = subscription.id;

    -- Keep the compatibility plan key synchronized. Do not change tenant
    -- status: an administratively suspended tenant must remain suspended.
    update public.tenants
    set plan = invoice.plan_key_snapshot
    where id = pay.tenant_id;
  end if;

  insert into public.entitlement_audit_logs (
    tenant_id, action, entity_type, entity_id, reason,
    previous_value, new_value
  ) values (
    pay.tenant_id,
    case when p_verified then 'billing.payment_verified' else 'billing.payment_rejected' end,
    'billing_payment', pay.id, nullif(trim(p_reason), ''),
    jsonb_build_object('status', 'recorded'),
    jsonb_build_object(
      'status', case when p_verified then 'verified' else 'rejected' end,
      'invoice_id', invoice.id,
      'plan_id', invoice.plan_id,
      'service_ends_at', case when p_verified then service_end else null end
    )
  );
end
$function$;

revoke all on function public.platform_record_manual_payment(
  uuid, uuid, numeric, text, text, text, timestamptz
) from public, anon;
revoke all on function public.platform_verify_manual_payment(
  uuid, boolean, text
) from public, anon;
revoke all on function public.platform_void_billing_invoice(uuid, text)
from public, anon;

grant execute on function public.platform_record_manual_payment(
  uuid, uuid, numeric, text, text, text, timestamptz
) to authenticated, service_role;
grant execute on function public.platform_verify_manual_payment(
  uuid, boolean, text
) to authenticated, service_role;
grant execute on function public.platform_void_billing_invoice(uuid, text)
to authenticated, service_role;
