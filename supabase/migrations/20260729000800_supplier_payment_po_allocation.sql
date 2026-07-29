-- Allocate supplier payments to a received purchase order while keeping the
-- supplier payable and paying-account ledger update atomic.

alter table public.supplier_payments
  add column if not exists purchase_order_id uuid;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'supplier_payments_purchase_order_id_fkey'
      and conrelid = 'public.supplier_payments'::regclass
  ) then
    alter table public.supplier_payments
      add constraint supplier_payments_purchase_order_id_fkey
      foreign key (purchase_order_id) references public.purchase_orders(id)
      on delete restrict not valid;
  end if;
end
$block$;

alter table public.supplier_payments
  alter constraint supplier_payments_ledger_transaction_id_fkey
  deferrable initially deferred;

create index if not exists idx_supplier_payments_purchase_order
  on public.supplier_payments(purchase_order_id)
  where purchase_order_id is not null;

create or replace function public.record_supplier_payment_v3(
  p_payment_id uuid,
  p_tenant_id uuid,
  p_branch_id uuid,
  p_supplier_id uuid,
  p_purchase_order_id uuid,
  p_amount numeric,
  p_method text,
  p_note text,
  p_account_id uuid,
  p_ledger_transaction_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_po public.purchase_orders%rowtype;
  v_allocated numeric;
  v_result boolean;
  v_existing_po_id uuid;
begin
  if p_purchase_order_id is null then
    raise exception using errcode = '22023',
      message = 'Select a purchase order for supplier payment.';
  end if;

  select purchase_order_id into v_existing_po_id
  from public.supplier_payments where id = p_payment_id;
  if found and v_existing_po_id is distinct from p_purchase_order_id then
    raise exception using errcode = '23505',
      message = 'Supplier payment purchase order conflicts.';
  end if;

  select po.* into v_po
  from public.purchase_orders po
  where po.id = p_purchase_order_id
  for update;

  if v_po.id is null
     or v_po.tenant_id <> p_tenant_id
     or v_po.branch_id <> p_branch_id
     or v_po.supplier_id <> p_supplier_id
     or v_po.status = 'cancelled' then
    raise exception using errcode = '22023',
      message = 'Supplier payment purchase order is invalid.';
  end if;

  select coalesce(sum(payment.amount), 0)
  into v_allocated
  from public.supplier_payments payment
  where payment.purchase_order_id = p_purchase_order_id
    and payment.id <> p_payment_id;

  if coalesce(v_po.total_received_cost, 0) - v_allocated + 0.01 < p_amount then
    raise exception using errcode = '23514',
      message = 'Payment exceeds purchase order pending amount.';
  end if;

  v_result := public.record_supplier_payment_v2(
    p_payment_id, p_tenant_id, p_branch_id, p_supplier_id, p_amount,
    p_method, p_note, p_account_id, p_ledger_transaction_id
  );

  update public.supplier_payments
  set purchase_order_id = p_purchase_order_id
  where id = p_payment_id
    and purchase_order_id is null;

  return v_result;
end
$function$;

revoke all on function public.record_supplier_payment_v3(
  uuid,uuid,uuid,uuid,uuid,numeric,text,text,uuid,uuid
) from public, anon;
grant execute on function public.record_supplier_payment_v3(
  uuid,uuid,uuid,uuid,uuid,numeric,text,text,uuid,uuid
) to authenticated, service_role;
