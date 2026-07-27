-- Additive POS payment-to-account linkage.
-- This migration intentionally does not mutate account balances. Atomic ledger
-- posting is enabled by a later migration after linkage survives all sync paths.

alter table public.sale_payments
  add column if not exists account_id uuid,
  add column if not exists ledger_transaction_id uuid;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sale_payments_account_id_fkey'
      and conrelid = 'public.sale_payments'::regclass
  ) then
    alter table public.sale_payments
      add constraint sale_payments_account_id_fkey
      foreign key (account_id)
      references public.accounts(id)
      on delete restrict
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sale_payments_ledger_transaction_id_fkey'
      and conrelid = 'public.sale_payments'::regclass
  ) then
    alter table public.sale_payments
      add constraint sale_payments_ledger_transaction_id_fkey
      foreign key (ledger_transaction_id)
      references public.account_transactions(id)
      on delete restrict
      not valid;
  end if;
end
$block$;

create index if not exists idx_sale_payments_account
  on public.sale_payments(account_id)
  where account_id is not null;

create unique index if not exists idx_sale_payments_ledger_transaction
  on public.sale_payments(ledger_transaction_id)
  where ledger_transaction_id is not null;

comment on column public.sale_payments.account_id is
  'Actual account that received this non-credit POS payment.';
comment on column public.sale_payments.ledger_transaction_id is
  'Ledger transaction posted atomically for this payment leg.';

create or replace function public.commit_pos_sale_v2(p_sale jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_sale_id uuid := (p_sale->>'id')::uuid;
  v_branch_id uuid := (p_sale->>'branch_id')::uuid;
  v_tenant_id uuid;
  v_committed boolean;
  v_payment record;
  v_account public.accounts%rowtype;
  v_ledger_row_count integer;
begin
  select branch.tenant_id
  into v_tenant_id
  from public.branches branch
  where branch.id = v_branch_id;

  if v_tenant_id is null then
    raise exception using errcode = '22023',
      message = 'Sale branch is invalid.';
  end if;

  if not public.current_user_has_branch_permission(
    v_tenant_id,
    v_branch_id,
    'pos.sale.create'
  ) then
    raise exception using errcode = '42501',
      message = 'POS sale permission is required.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(
      coalesce(p_sale->'sale_payments', '[]'::jsonb)
    ) payment
    group by lower(payment->>'method')
    having count(*) > 1
  ) then
    raise exception using errcode = '22023',
      message = 'Each POS payment method may appear only once.';
  end if;

  for v_payment in
    select
      (value->>'id')::uuid as payment_id,
      lower(value->>'method') as method,
      (value->>'amount')::numeric as amount,
      nullif(value->>'account_id', '')::uuid as account_id,
      nullif(value->>'ledger_transaction_id', '')::uuid
        as ledger_transaction_id
    from jsonb_array_elements(
      coalesce(p_sale->'sale_payments', '[]'::jsonb)
    )
  loop
    if v_payment.payment_id is null
       or v_payment.amount is null
       or v_payment.amount <= 0 then
      raise exception using errcode = '22023',
        message = 'POS payment identity or amount is invalid.';
    end if;

    if v_payment.method = 'credit' then
      if v_payment.account_id is not null
         or v_payment.ledger_transaction_id is not null then
        raise exception using errcode = '22023',
          message = 'Credit payment cannot be linked to a cash account.';
      end if;
      continue;
    end if;

    if v_payment.method not in ('cash', 'easypaisa', 'jazzcash', 'card')
       or v_payment.account_id is null
       or v_payment.ledger_transaction_id is null then
      raise exception using errcode = '22023',
        message = 'Non-credit payment requires an account and ledger id.';
    end if;

    select account.*
    into v_account
    from public.accounts account
    where account.id = v_payment.account_id
    for update;

    if v_account.id is null
       or v_account.tenant_id <> v_tenant_id
       or v_account.branch_id <> v_branch_id
       or not v_account.is_active
       or (
         v_payment.method = 'cash'
         and v_account.account_type <> 'cash'
       )
       or (
         v_payment.method in ('easypaisa', 'jazzcash')
         and v_account.account_type <> 'mobile_wallet'
       )
       or (
         v_payment.method = 'card'
         and v_account.account_type not in ('card', 'bank')
       ) then
      raise exception using errcode = '22023',
        message = 'Payment account is inactive, incompatible, or cross-branch.';
    end if;
  end loop;

  v_committed := public.commit_pos_sale(p_sale);

  for v_payment in
    select
      (value->>'id')::uuid as payment_id,
      lower(value->>'method') as method,
      (value->>'amount')::numeric as amount,
      nullif(value->>'account_id', '')::uuid as account_id,
      nullif(value->>'ledger_transaction_id', '')::uuid
        as ledger_transaction_id
    from jsonb_array_elements(
      coalesce(p_sale->'sale_payments', '[]'::jsonb)
    )
    where lower(value->>'method') <> 'credit'
  loop
    insert into public.account_transactions (
      id,
      tenant_id,
      branch_id,
      account_id,
      transaction_type,
      direction,
      amount,
      description,
      reference_type,
      reference_id,
      source_event_key,
      transaction_at,
      created_by,
      created_at
    )
    values (
      v_payment.ledger_transaction_id,
      v_tenant_id,
      v_branch_id,
      v_payment.account_id,
      'sale',
      'in',
      v_payment.amount,
      'POS ' || initcap(v_payment.method) || ' payment',
      'pos_sale_payment',
      v_payment.payment_id::text,
      'pos:sale:' || v_sale_id::text ||
        ':payment:' || v_payment.payment_id::text,
      coalesce((p_sale->>'created_at')::timestamptz, now()),
      auth.uid(),
      now()
    )
    on conflict (id) do nothing;

    get diagnostics v_ledger_row_count = row_count;
    if v_ledger_row_count = 1 then
      update public.accounts
      set current_balance = current_balance + v_payment.amount,
          updated_at = now()
      where id = v_payment.account_id;
    elsif not exists (
      select 1
      from public.account_transactions transaction
      where transaction.id = v_payment.ledger_transaction_id
        and transaction.tenant_id = v_tenant_id
        and transaction.branch_id = v_branch_id
        and transaction.account_id = v_payment.account_id
        and transaction.transaction_type = 'sale'
        and transaction.direction = 'in'
        and transaction.amount = v_payment.amount
        and transaction.reference_id = v_payment.payment_id::text
    ) then
      raise exception using errcode = '23505',
        message = 'POS ledger id is already used by another transaction.';
    end if;

    update public.sale_payments payment
    set id = v_payment.payment_id,
        account_id = v_payment.account_id,
        ledger_transaction_id = v_payment.ledger_transaction_id
    where payment.sale_id = v_sale_id
      and lower(payment.method) = v_payment.method
      and (
        payment.ledger_transaction_id is null
        or payment.ledger_transaction_id = v_payment.ledger_transaction_id
      );

    if not found then
      raise exception using errcode = '23514',
        message = 'POS payment linkage conflicts with the committed sale.';
    end if;
  end loop;

  return v_committed;
end
$function$;

revoke all on function public.commit_pos_sale_v2(jsonb)
from public, anon;
grant execute on function public.commit_pos_sale_v2(jsonb)
to authenticated, service_role;
