-- Repair charge and cash receipt are separate facts. This table records only
-- explicit receipts and posts each receipt to exactly one receiving account.

create table if not exists public.repair_payments (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  ticket_id uuid not null references public.repair_tickets(id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  method text not null check (method in ('cash', 'easypaisa', 'jazzcash', 'card')),
  account_id uuid not null references public.accounts(id) on delete restrict,
  ledger_transaction_id uuid not null
    references public.account_transactions(id) on delete restrict,
  note text,
  received_by uuid not null references public.users(id),
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists idx_repair_payment_ledger
  on public.repair_payments(ledger_transaction_id);
create index if not exists idx_repair_payments_ticket
  on public.repair_payments(ticket_id, received_at);

alter table public.repair_payments enable row level security;
drop policy if exists "tenant users can read repair payments"
  on public.repair_payments;
create policy "tenant users can read repair payments"
on public.repair_payments for select to authenticated
using (
  public.current_user_has_branch_permission(
    tenant_id, branch_id, 'repair.ticket.view'
  )
);

create or replace function public.record_repair_payment_v2(
  p_payment_id uuid,
  p_ticket_id uuid,
  p_amount numeric,
  p_method text,
  p_account_id uuid,
  p_ledger_transaction_id uuid,
  p_note text default null,
  p_received_at timestamptz default now()
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_ticket public.repair_tickets%rowtype;
  v_account public.accounts%rowtype;
  v_existing public.repair_payments%rowtype;
  v_paid numeric;
  v_method text := lower(coalesce(p_method, 'cash'));
begin
  if p_payment_id is null or p_ticket_id is null or p_account_id is null
     or p_ledger_transaction_id is null or p_amount is null or p_amount <= 0
     or v_method not in ('cash', 'easypaisa', 'jazzcash', 'card') then
    raise exception using errcode = '22023',
      message = 'Repair payment identity, method, account, or amount is invalid.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_payment_id::text, 0));
  select payment.* into v_existing
  from public.repair_payments payment
  where payment.id = p_payment_id;
  if v_existing.id is not null then
    if v_existing.ticket_id is distinct from p_ticket_id
       or v_existing.amount is distinct from p_amount
       or v_existing.method is distinct from v_method
       or v_existing.account_id is distinct from p_account_id
       or v_existing.ledger_transaction_id
          is distinct from p_ledger_transaction_id then
      raise exception using errcode = '23505',
        message = 'Repair payment identity conflicts.';
    end if;
    return false;
  end if;

  select ticket.* into v_ticket
  from public.repair_tickets ticket
  where ticket.id = p_ticket_id
  for update;
  if v_ticket.id is null or v_ticket.status = 'cancelled'
     or v_ticket.total_cost is null then
    raise exception using errcode = '23514',
      message = 'Repair ticket cannot receive payment.';
  end if;
  if not public.current_user_has_branch_permission(
    v_ticket.tenant_id, v_ticket.branch_id, 'repair.payment.create'
  ) then
    raise exception using errcode = '42501',
      message = 'Repair payment permission is required.';
  end if;

  select account.* into v_account
  from public.accounts account
  where account.id = p_account_id
  for update;
  if v_account.id is null
     or v_account.tenant_id <> v_ticket.tenant_id
     or v_account.branch_id <> v_ticket.branch_id
     or not v_account.is_active
     or (v_method = 'cash' and v_account.account_type <> 'cash')
     or (v_method in ('easypaisa', 'jazzcash')
         and v_account.account_type <> 'mobile_wallet')
     or (v_method = 'card'
         and v_account.account_type not in ('card', 'bank')) then
    raise exception using errcode = '22023',
      message = 'Repair receiving account is incompatible.';
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.repair_payments
  where ticket_id = p_ticket_id;
  if v_paid + p_amount > v_ticket.total_cost + 0.01 then
    raise exception using errcode = '23514',
      message = 'Payment exceeds the repair balance.';
  end if;

  insert into public.account_transactions (
    id, tenant_id, branch_id, account_id, transaction_type, direction,
    amount, description, reference_type, reference_id, source_event_key,
    transaction_at, created_by, created_at
  ) values (
    p_ledger_transaction_id, v_ticket.tenant_id, v_ticket.branch_id,
    p_account_id, 'other', 'in', p_amount, 'Repair payment',
    'repair_payment', p_payment_id::text,
    'repair:payment:' || p_payment_id::text,
    coalesce(p_received_at, now()), auth.uid(), now()
  );

  insert into public.repair_payments (
    id, tenant_id, branch_id, ticket_id, amount, method, account_id,
    ledger_transaction_id, note, received_by, received_at
  ) values (
    p_payment_id, v_ticket.tenant_id, v_ticket.branch_id, p_ticket_id,
    p_amount, v_method, p_account_id, p_ledger_transaction_id, p_note,
    auth.uid(), coalesce(p_received_at, now())
  );

  update public.accounts
  set current_balance = current_balance + p_amount, updated_at = now()
  where id = p_account_id;
  return true;
end
$function$;

revoke all on function public.record_repair_payment_v2(
  uuid, uuid, numeric, text, uuid, uuid, text, timestamptz
) from public, anon;
grant execute on function public.record_repair_payment_v2(
  uuid, uuid, numeric, text, uuid, uuid, text, timestamptz
) to authenticated, service_role;
