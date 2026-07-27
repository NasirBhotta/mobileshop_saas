-- Enforce branch-aware account permissions on legacy mutations and table RLS.

create or replace function public.record_account_transaction(
  p_transaction_id uuid,
  p_tenant_id uuid,
  p_branch_id uuid,
  p_account_id uuid,
  p_transaction_type text,
  p_direction text,
  p_amount numeric,
  p_description text default null,
  p_reference_type text default null,
  p_reference_id text default null,
  p_transaction_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_inserted uuid;
  v_delta numeric;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero.';
  end if;

  if p_direction not in ('in', 'out') then
    raise exception 'Transaction direction is invalid.';
  end if;

  if not public.current_user_has_branch_permission(
    p_tenant_id,
    p_branch_id,
    'account.transaction.create'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Account transaction permission is required.';
  end if;

  if exists (
    select 1
    from public.account_transactions transaction
    where transaction.id = p_transaction_id
  ) then
    return p_transaction_id;
  end if;

  select account.*
  into v_account
  from public.accounts account
  where account.id = p_account_id
  for update;

  if v_account.id is null
     or v_account.tenant_id <> p_tenant_id
     or v_account.branch_id <> p_branch_id
     or not v_account.is_active then
    raise exception 'Account not found.';
  end if;

  v_delta := case when p_direction = 'in' then p_amount else -p_amount end;

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
    transaction_at,
    created_by
  )
  values (
    p_transaction_id,
    p_tenant_id,
    p_branch_id,
    p_account_id,
    p_transaction_type,
    p_direction,
    p_amount,
    p_description,
    p_reference_type,
    p_reference_id,
    coalesce(p_transaction_at, now()),
    auth.uid()
  )
  returning id into v_inserted;

  update public.accounts
  set current_balance = current_balance + v_delta
  where id = p_account_id;

  return v_inserted;
end;
$$;

revoke all on function public.record_account_transaction(
  uuid, uuid, uuid, uuid, text, text, numeric, text, text, text, timestamptz
) from public, anon;

grant execute on function public.record_account_transaction(
  uuid, uuid, uuid, uuid, text, text, numeric, text, text, text, timestamptz
) to authenticated;

drop policy if exists "tenant users can manage accounts"
on public.accounts;

drop policy if exists "tenant users can manage account transactions"
on public.account_transactions;

drop policy if exists "branch users can read accounts"
on public.accounts;
create policy "branch users can read accounts"
on public.accounts
for select to authenticated
using (
  public.current_user_has_branch_permission(
    tenant_id,
    branch_id,
    'account.account.view'
  )
);

drop policy if exists "branch users can create accounts"
on public.accounts;
create policy "branch users can create accounts"
on public.accounts
for insert to authenticated
with check (
  public.current_user_has_branch_permission(
    tenant_id,
    branch_id,
    'account.account.create'
  )
);

drop policy if exists "branch users can update accounts"
on public.accounts;
create policy "branch users can update accounts"
on public.accounts
for update to authenticated
using (
  public.current_user_has_branch_permission(
    tenant_id,
    branch_id,
    'account.account.update'
  )
)
with check (
  public.current_user_has_branch_permission(
    tenant_id,
    branch_id,
    'account.account.update'
  )
);

drop policy if exists "branch users can delete accounts"
on public.accounts;
create policy "branch users can delete accounts"
on public.accounts
for delete to authenticated
using (
  public.current_user_has_branch_permission(
    tenant_id,
    branch_id,
    'account.account.update'
  )
);

drop policy if exists "branch users can read account transactions"
on public.account_transactions;
create policy "branch users can read account transactions"
on public.account_transactions
for select to authenticated
using (
  public.current_user_has_branch_permission(
    tenant_id,
    branch_id,
    'account.transaction.view'
  )
);

-- No direct INSERT/UPDATE/DELETE policy is created for ledger rows. Financial
-- mutations must pass through the audited SECURITY DEFINER RPCs.
