-- Atomically settle customer receivables into an actual monetary account.

alter table public.customer_settlements
  add column if not exists account_id uuid,
  add column if not exists ledger_transaction_id uuid;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'customer_settlements_account_id_fkey'
      and conrelid = 'public.customer_settlements'::regclass
  ) then
    alter table public.customer_settlements
      add constraint customer_settlements_account_id_fkey
      foreign key (account_id) references public.accounts(id)
      on delete restrict not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'customer_settlements_ledger_transaction_id_fkey'
      and conrelid = 'public.customer_settlements'::regclass
  ) then
    alter table public.customer_settlements
      add constraint customer_settlements_ledger_transaction_id_fkey
      foreign key (ledger_transaction_id)
      references public.account_transactions(id)
      on delete restrict not valid;
  end if;
end
$block$;

create unique index if not exists idx_customer_settlement_ledger
  on public.customer_settlements(ledger_transaction_id)
  where ledger_transaction_id is not null;

create or replace function public.commit_customer_settlement(
  p_settlement jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_id uuid := (p_settlement->>'id')::uuid;
  v_customer_id uuid := (p_settlement->>'customer_id')::uuid;
  v_branch_id uuid := (p_settlement->>'branch_id')::uuid;
  v_user_id uuid := (p_settlement->>'user_id')::uuid;
  v_account_id uuid := (p_settlement->>'account_id')::uuid;
  v_ledger_id uuid := (p_settlement->>'ledger_transaction_id')::uuid;
  v_amount numeric := (p_settlement->>'amount')::numeric;
  v_method text := lower(p_settlement->>'method');
  v_created_at timestamptz :=
    coalesce((p_settlement->>'created_at')::timestamptz, now());
  v_tenant_id uuid;
  v_customer public.customers%rowtype;
  v_account public.accounts%rowtype;
  v_existing public.customer_settlements%rowtype;
begin
  if v_id is null or v_customer_id is null or v_branch_id is null
     or v_user_id is null or v_account_id is null or v_ledger_id is null
     or v_amount is null or v_amount <= 0 then
    raise exception using errcode = '22023',
      message = 'Settlement identity, account, or amount is invalid.';
  end if;

  if v_user_id <> auth.uid() then
    raise exception using errcode = '42501',
      message = 'Settlement actor does not match the authenticated user.';
  end if;

  select branch.tenant_id
  into v_tenant_id
  from public.branches branch
  where branch.id = v_branch_id;

  if v_tenant_id is null or not public.current_user_has_branch_permission(
    v_tenant_id,
    v_branch_id,
    'customer.credit.settle'
  ) then
    raise exception using errcode = '42501',
      message = 'Customer settlement permission is required.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

  select settlement.*
  into v_existing
  from public.customer_settlements settlement
  where settlement.id = v_id;

  if v_existing.id is not null then
    if v_existing.customer_id is distinct from v_customer_id
       or v_existing.branch_id is distinct from v_branch_id
       or v_existing.user_id is distinct from v_user_id
       or v_existing.amount is distinct from v_amount
       or lower(v_existing.method) is distinct from v_method
       or v_existing.account_id is distinct from v_account_id
       or v_existing.ledger_transaction_id is distinct from v_ledger_id then
      raise exception using errcode = '23505',
        message = 'Settlement id is already used by different data.';
    end if;
    return false;
  end if;

  select customer.*
  into v_customer
  from public.customers customer
  where customer.id = v_customer_id
  for update;

  select account.*
  into v_account
  from public.accounts account
  where account.id = v_account_id
  for update;

  if v_customer.id is null
     or v_customer.tenant_id <> v_tenant_id
     or v_customer.branch_id <> v_branch_id then
    raise exception using errcode = '22023',
      message = 'Settlement customer context is invalid.';
  end if;

  if v_account.id is null
     or v_account.tenant_id <> v_tenant_id
     or v_account.branch_id <> v_branch_id
     or not v_account.is_active
     or (
       v_method = 'cash' and v_account.account_type <> 'cash'
     )
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
      message = 'Settlement receiving account is incompatible.';
  end if;

  if coalesce(v_customer.outstanding_balance, 0) + 0.01 < v_amount then
    raise exception using errcode = '23514',
      message = 'Settlement exceeds current customer dues.';
  end if;

  insert into public.customer_settlements (
    id, customer_id, branch_id, user_id, amount, method, account_id,
    ledger_transaction_id, notes, created_at
  )
  values (
    v_id, v_customer_id, v_branch_id, v_user_id, v_amount, v_method,
    v_account_id, v_ledger_id, nullif(p_settlement->>'notes', ''),
    v_created_at
  );

  update public.customers
  set outstanding_balance =
    greatest(0, coalesce(outstanding_balance, 0) - v_amount)
  where id = v_customer_id;

  insert into public.account_transactions (
    id, tenant_id, branch_id, account_id, transaction_type, direction,
    amount, description, reference_type, reference_id, source_event_key,
    transaction_at, created_by, created_at
  )
  values (
    v_ledger_id, v_tenant_id, v_branch_id, v_account_id,
    'customer_payment', 'in', v_amount, 'Customer dues settlement',
    'customer_settlement', v_id::text, 'customer:settlement:' || v_id::text,
    v_created_at, v_user_id, now()
  );

  update public.accounts
  set current_balance = current_balance + v_amount,
      updated_at = now()
  where id = v_account_id;

  return true;
end
$function$;

revoke all on function public.commit_customer_settlement(jsonb)
from public, anon;
grant execute on function public.commit_customer_settlement(jsonb)
to authenticated, service_role;
