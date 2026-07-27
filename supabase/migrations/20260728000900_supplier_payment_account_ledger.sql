-- Atomically reduce supplier payable and the selected paying account.

alter table public.supplier_payments
  add column if not exists account_id uuid,
  add column if not exists ledger_transaction_id uuid;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'supplier_payments_account_id_fkey'
      and conrelid = 'public.supplier_payments'::regclass
  ) then
    alter table public.supplier_payments
      add constraint supplier_payments_account_id_fkey
      foreign key (account_id) references public.accounts(id)
      on delete restrict not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'supplier_payments_ledger_transaction_id_fkey'
      and conrelid = 'public.supplier_payments'::regclass
  ) then
    alter table public.supplier_payments
      add constraint supplier_payments_ledger_transaction_id_fkey
      foreign key (ledger_transaction_id)
      references public.account_transactions(id)
      on delete restrict not valid;
  end if;
end
$block$;

create unique index if not exists idx_supplier_payment_ledger
  on public.supplier_payments(ledger_transaction_id)
  where ledger_transaction_id is not null;

create or replace function public.record_supplier_payment_v2(
  p_payment_id uuid,
  p_tenant_id uuid,
  p_branch_id uuid,
  p_supplier_id uuid,
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
  v_supplier public.suppliers%rowtype;
  v_account public.accounts%rowtype;
  v_existing public.supplier_payments%rowtype;
  v_method text := lower(coalesce(p_method, 'cash'));
begin
  if p_payment_id is null or p_supplier_id is null
     or p_account_id is null or p_ledger_transaction_id is null
     or p_amount is null or p_amount <= 0 then
    raise exception using errcode = '22023',
      message = 'Supplier payment identity, account, or amount is invalid.';
  end if;

  if not public.current_user_has_branch_permission(
    p_tenant_id,
    p_branch_id,
    'supplier.payment.create'
  ) then
    raise exception using errcode = '42501',
      message = 'Supplier payment permission is required.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_payment_id::text, 0));
  select payment.*
  into v_existing
  from public.supplier_payments payment
  where payment.id = p_payment_id;

  if v_existing.id is not null then
    if v_existing.tenant_id is distinct from p_tenant_id
       or v_existing.branch_id is distinct from p_branch_id
       or v_existing.supplier_id is distinct from p_supplier_id
       or v_existing.amount is distinct from p_amount
       or lower(v_existing.method) is distinct from v_method
       or v_existing.account_id is distinct from p_account_id
       or v_existing.ledger_transaction_id
          is distinct from p_ledger_transaction_id then
      raise exception using errcode = '23505',
        message = 'Supplier payment identity conflicts.';
    end if;
    return false;
  end if;

  select supplier.*
  into v_supplier
  from public.suppliers supplier
  where supplier.id = p_supplier_id
  for update;
  select account.*
  into v_account
  from public.accounts account
  where account.id = p_account_id
  for update;

  if v_supplier.id is null
     or v_supplier.tenant_id <> p_tenant_id
     or (v_supplier.branch_id is not null
         and v_supplier.branch_id <> p_branch_id) then
    raise exception using errcode = '22023',
      message = 'Supplier context is invalid.';
  end if;

  if v_account.id is null
     or v_account.tenant_id <> p_tenant_id
     or v_account.branch_id <> p_branch_id
     or not v_account.is_active
     or (v_method = 'cash' and v_account.account_type <> 'cash')
     or (
       v_method in ('easypaisa', 'jazzcash')
       and v_account.account_type <> 'mobile_wallet'
     )
     or (
       v_method = 'card'
       and v_account.account_type not in ('card', 'bank')
     )
     or v_method not in ('cash', 'easypaisa', 'jazzcash', 'card') then
    raise exception using errcode = '22023',
      message = 'Supplier paying account is incompatible.';
  end if;

  if coalesce(v_supplier.outstanding_balance, 0) + 0.01 < p_amount then
    raise exception using errcode = '23514',
      message = 'Payment exceeds supplier outstanding balance.';
  end if;
  if v_account.current_balance + 0.01 < p_amount then
    raise exception using errcode = '23514',
      message = 'Paying account balance is insufficient.';
  end if;

  insert into public.supplier_payments (
    id, tenant_id, branch_id, supplier_id, amount, method, account_id,
    ledger_transaction_id, note, paid_by, paid_at
  )
  values (
    p_payment_id, p_tenant_id, p_branch_id, p_supplier_id, p_amount,
    v_method, p_account_id, p_ledger_transaction_id, p_note, auth.uid(), now()
  );

  update public.suppliers
  set outstanding_balance = greatest(outstanding_balance - p_amount, 0),
      updated_at = now()
  where id = p_supplier_id;

  insert into public.account_transactions (
    id, tenant_id, branch_id, account_id, transaction_type, direction,
    amount, description, reference_type, reference_id, source_event_key,
    transaction_at, created_by, created_at
  )
  values (
    p_ledger_transaction_id, p_tenant_id, p_branch_id, p_account_id,
    'supplier_payment', 'out', p_amount, 'Supplier payment',
    'supplier_payment', p_payment_id::text,
    'supplier:payment:' || p_payment_id::text, now(), auth.uid(), now()
  );

  update public.accounts
  set current_balance = current_balance - p_amount,
      updated_at = now()
  where id = p_account_id;

  return true;
end
$function$;

revoke all on function public.record_supplier_payment_v2(
  uuid, uuid, uuid, uuid, numeric, text, text, uuid, uuid
) from public, anon;
grant execute on function public.record_supplier_payment_v2(
  uuid, uuid, uuid, uuid, numeric, text, text, uuid, uuid
) to authenticated, service_role;
