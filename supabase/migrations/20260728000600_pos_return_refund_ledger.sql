-- Connect approved cash refunds to the exact original POS payment accounts.

create table if not exists public.sale_return_refund_legs (
  id uuid primary key,
  return_id uuid not null
    references public.sale_returns(id) on delete restrict,
  original_payment_id uuid not null
    references public.sale_payments(id) on delete restrict,
  account_id uuid not null
    references public.accounts(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  ledger_transaction_id uuid not null unique
    references public.account_transactions(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (return_id, original_payment_id)
);

create index if not exists idx_return_refund_original_payment
  on public.sale_return_refund_legs(original_payment_id);

alter table public.sale_return_refund_legs enable row level security;

drop policy if exists "branch users can read refund legs"
on public.sale_return_refund_legs;
create policy "branch users can read refund legs"
on public.sale_return_refund_legs
for select
using (
  exists (
    select 1
    from public.sale_returns sale_return
    join public.branches branch on branch.id = sale_return.branch_id
    join public.users app_user on app_user.tenant_id = branch.tenant_id
    where sale_return.id = sale_return_refund_legs.return_id
      and app_user.id = auth.uid()
  )
);

create or replace function public.post_pos_return_refund(
  p_return_id uuid,
  p_refund_legs jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_return public.sale_returns%rowtype;
  v_tenant_id uuid;
  v_requested_total numeric;
  v_existing_total numeric;
  v_leg record;
  v_payment record;
  v_prior_refunded numeric;
  v_ledger_row_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_return_id::text, 0));

  select sale_return.*
  into v_return
  from public.sale_returns sale_return
  where sale_return.id = p_return_id
  for update of sale_return;

  select branch.tenant_id
  into v_tenant_id
  from public.branches branch
  where branch.id = v_return.branch_id;

  if v_return.id is null
     or v_return.status <> 'approved'
     or v_return.refund_method <> 'cash' then
    raise exception using errcode = '22023',
      message = 'Only an approved cash return can post a monetary refund.';
  end if;

  if not public.current_user_has_branch_permission(
    v_tenant_id,
    v_return.branch_id,
    'pos.sale.return'
  ) then
    raise exception using errcode = '42501',
      message = 'POS return permission is required.';
  end if;

  if jsonb_typeof(p_refund_legs) <> 'array'
     or jsonb_array_length(p_refund_legs) = 0 then
    raise exception using errcode = '22023',
      message = 'Cash refund allocation is required.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_refund_legs) leg
    group by (leg->>'original_payment_id')::uuid
    having count(*) > 1
  ) then
    raise exception using errcode = '22023',
      message = 'A payment can appear only once in a refund allocation.';
  end if;

  select coalesce(sum((leg->>'amount')::numeric), 0)
  into v_requested_total
  from jsonb_array_elements(p_refund_legs) leg;

  if abs(v_requested_total - v_return.refund_amount) > 0.01 then
    raise exception using errcode = '22023',
      message = 'Refund allocation does not match the approved amount.';
  end if;

  select coalesce(sum(refund_leg.amount), 0)
  into v_existing_total
  from public.sale_return_refund_legs refund_leg
  where refund_leg.return_id = p_return_id;

  if abs(v_existing_total - v_return.refund_amount) <= 0.01 then
    return false;
  elsif v_existing_total > 0 then
    raise exception using errcode = '23514',
      message = 'Refund ledger is partially posted and requires reconciliation.';
  end if;

  for v_leg in
    select
      (value->>'id')::uuid as id,
      (value->>'original_payment_id')::uuid as original_payment_id,
      (value->>'account_id')::uuid as account_id,
      (value->>'amount')::numeric as amount,
      (value->>'ledger_transaction_id')::uuid as ledger_transaction_id
    from jsonb_array_elements(p_refund_legs)
    order by (value->>'original_payment_id')::uuid
  loop
    select
      payment.id,
      payment.sale_id,
      payment.account_id,
      payment.amount,
      payment.method,
      account.tenant_id,
      account.branch_id,
      account.is_active
    into v_payment
    from public.sale_payments payment
    join public.accounts account on account.id = payment.account_id
    where payment.id = v_leg.original_payment_id
    for update of account;

    if v_leg.id is null
       or v_leg.ledger_transaction_id is null
       or v_leg.amount is null
       or v_leg.amount <= 0
       or v_payment.id is null
       or v_payment.sale_id <> v_return.original_sale_id
       or v_payment.method = 'credit'
       or v_payment.account_id <> v_leg.account_id
       or v_payment.tenant_id <> v_tenant_id
       or v_payment.branch_id <> v_return.branch_id
       or not v_payment.is_active then
      raise exception using errcode = '22023',
        message = 'Refund allocation has an invalid original payment account.';
    end if;

    select coalesce(sum(refund_leg.amount), 0)
    into v_prior_refunded
    from public.sale_return_refund_legs refund_leg
    where refund_leg.original_payment_id = v_leg.original_payment_id
      and refund_leg.return_id <> p_return_id;

    if v_prior_refunded + v_leg.amount > v_payment.amount + 0.01 then
      raise exception using errcode = '23514',
        message = 'Refund exceeds the original payment capacity.';
    end if;

    insert into public.account_transactions (
      id, tenant_id, branch_id, account_id, transaction_type, direction,
      amount, description, reference_type, reference_id, source_event_key,
      transaction_at, created_by, created_at
    )
    values (
      v_leg.ledger_transaction_id,
      v_tenant_id,
      v_return.branch_id,
      v_leg.account_id,
      'other',
      'out',
      v_leg.amount,
      'POS sale refund',
      'pos_sale_refund',
      v_leg.id::text,
      'pos:return:' || p_return_id::text ||
        ':payment:' || v_leg.original_payment_id::text,
      v_return.created_at,
      coalesce(v_return.approved_by, v_return.user_id),
      now()
    )
    on conflict (id) do nothing;

    get diagnostics v_ledger_row_count = row_count;
    if v_ledger_row_count <> 1 then
      raise exception using errcode = '23505',
        message = 'Refund ledger id is already in use.';
    end if;

    update public.accounts
    set current_balance = current_balance - v_leg.amount,
        updated_at = now()
    where id = v_leg.account_id;

    insert into public.sale_return_refund_legs (
      id, return_id, original_payment_id, account_id, amount,
      ledger_transaction_id
    )
    values (
      v_leg.id, p_return_id, v_leg.original_payment_id, v_leg.account_id,
      v_leg.amount, v_leg.ledger_transaction_id
    );
  end loop;

  return true;
end
$function$;

revoke all on function public.post_pos_return_refund(uuid, jsonb)
from public, anon;
grant execute on function public.post_pos_return_refund(uuid, jsonb)
to authenticated, service_role;
