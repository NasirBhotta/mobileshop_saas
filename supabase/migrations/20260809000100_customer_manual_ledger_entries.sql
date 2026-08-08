-- Manual customer balance adjustments, independent of sales and cash receipts.
-- Cash received against dues continues to use commit_customer_settlement so an
-- account transaction is always created exactly once.

create table if not exists public.customer_ledger_entries (
  id uuid primary key,
  customer_id uuid not null references public.customers(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  entry_type text not null check (entry_type in ('charge', 'credit')),
  amount numeric not null check (amount > 0),
  reason text not null check (length(trim(reason)) > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_customer_ledger_entries_customer
on public.customer_ledger_entries(customer_id, created_at desc);

alter table public.customer_ledger_entries enable row level security;

drop policy if exists "branch users read customer ledger entries"
on public.customer_ledger_entries;
create policy "branch users read customer ledger entries"
on public.customer_ledger_entries for select to authenticated
using (public.current_user_can_access_branch(branch_id));

revoke all on public.customer_ledger_entries from public, anon, authenticated;
grant select on public.customer_ledger_entries to authenticated;
grant all on public.customer_ledger_entries to service_role;

create or replace function public.commit_customer_ledger_entry(p_entry jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_id uuid := (p_entry->>'id')::uuid;
  v_customer_id uuid := (p_entry->>'customer_id')::uuid;
  v_branch_id uuid := (p_entry->>'branch_id')::uuid;
  v_user_id uuid := (p_entry->>'user_id')::uuid;
  v_type text := lower(p_entry->>'entry_type');
  v_amount numeric := (p_entry->>'amount')::numeric;
  v_reason text := trim(p_entry->>'reason');
  v_created_at timestamptz := coalesce(
    (p_entry->>'created_at')::timestamptz,
    now()
  );
  v_customer public.customers%rowtype;
  v_tenant_id uuid;
  v_existing public.customer_ledger_entries%rowtype;
begin
  if v_id is null or v_customer_id is null or v_branch_id is null
     or v_user_id is null or v_amount is null or v_amount <= 0
     or v_type not in ('charge', 'credit') or v_reason = '' then
    raise exception using errcode = '22023',
      message = 'Customer ledger entry is invalid.';
  end if;

  if v_user_id <> auth.uid() then
    raise exception using errcode = '42501',
      message = 'Ledger actor does not match the authenticated user.';
  end if;

  select branch.tenant_id into v_tenant_id
  from public.branches branch where branch.id = v_branch_id;

  if v_tenant_id is null or not public.current_user_has_branch_permission(
    v_tenant_id, v_branch_id, 'customer.credit.settle'
  ) then
    raise exception using errcode = '42501',
      message = 'Customer ledger adjustment permission is required.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

  select entry.* into v_existing
  from public.customer_ledger_entries entry where entry.id = v_id;
  if v_existing.id is not null then
    if v_existing.customer_id is distinct from v_customer_id
       or v_existing.branch_id is distinct from v_branch_id
       or v_existing.user_id is distinct from v_user_id
       or v_existing.entry_type is distinct from v_type
       or v_existing.amount is distinct from v_amount
       or v_existing.reason is distinct from v_reason then
      raise exception using errcode = '23505',
        message = 'Ledger entry id is already used by different data.';
    end if;
    return false;
  end if;

  select customer.* into v_customer
  from public.customers customer
  where customer.id = v_customer_id for update;

  if v_customer.id is null or v_customer.tenant_id <> v_tenant_id
     or v_customer.branch_id <> v_branch_id then
    raise exception using errcode = '22023',
      message = 'Customer ledger context is invalid.';
  end if;

  if v_type = 'credit'
     and coalesce(v_customer.outstanding_balance, 0) + 0.01 < v_amount then
    raise exception using errcode = '23514',
      message = 'Ledger credit exceeds current customer dues.';
  end if;

  insert into public.customer_ledger_entries (
    id, customer_id, branch_id, user_id, entry_type, amount, reason, created_at
  ) values (
    v_id, v_customer_id, v_branch_id, v_user_id, v_type, v_amount,
    v_reason, v_created_at
  );

  update public.customers
  set outstanding_balance = greatest(
    0,
    coalesce(outstanding_balance, 0)
      + case when v_type = 'charge' then v_amount else -v_amount end
  )
  where id = v_customer_id;

  return true;
end
$function$;

revoke all on function public.commit_customer_ledger_entry(jsonb)
from public, anon;
grant execute on function public.commit_customer_ledger_entry(jsonb)
to authenticated, service_role;
