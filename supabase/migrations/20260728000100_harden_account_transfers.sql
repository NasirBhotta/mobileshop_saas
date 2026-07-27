-- Align account-transfer validation with the offline/local ledger.
-- Additive deployment: replaces the RPC in place without rewriting data.

create or replace function public.record_account_transfer(
  p_out_transaction_id uuid,
  p_in_transaction_id uuid,
  p_tenant_id uuid,
  p_branch_id uuid,
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_transfer_group_id uuid,
  p_amount numeric,
  p_description text default null,
  p_transaction_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from public.accounts%rowtype;
  v_to public.accounts%rowtype;
  v_out_exists boolean;
  v_in_exists boolean;
begin
  if p_out_transaction_id is null
     or p_in_transaction_id is null
     or p_out_transaction_id = p_in_transaction_id then
    raise exception 'Transfer ledger IDs must be different.';
  end if;

  if p_transfer_group_id is null then
    raise exception 'Transfer group is required.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero.';
  end if;

  if p_from_account_id = p_to_account_id then
    raise exception 'Select two different accounts.';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = p_tenant_id
  ) then
    raise exception 'Not allowed.';
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

  -- Serialize retries for one logical transfer before checking its two legs.
  perform pg_advisory_xact_lock(hashtext(p_transfer_group_id::text));

  select exists (
    select 1
    from public.account_transactions t
    where t.id = p_out_transaction_id
  )
  into v_out_exists;

  select exists (
    select 1
    from public.account_transactions t
    where t.id = p_in_transaction_id
  )
  into v_in_exists;

  if v_out_exists and v_in_exists then
    return p_transfer_group_id;
  end if;

  if v_out_exists <> v_in_exists then
    raise exception
      'Account transfer is incomplete and requires reconciliation.';
  end if;

  -- A stable lock order prevents opposite concurrent transfers deadlocking.
  perform 1
  from public.accounts a
  where a.id in (p_from_account_id, p_to_account_id)
  order by a.id
  for update;

  select a.*
  into v_from
  from public.accounts a
  where a.id = p_from_account_id;

  select a.*
  into v_to
  from public.accounts a
  where a.id = p_to_account_id;

  if v_from.id is null or v_to.id is null then
    raise exception 'Account not found.';
  end if;

  if not v_from.is_active or not v_to.is_active then
    raise exception 'Transfer account is inactive.';
  end if;

  if v_from.tenant_id <> p_tenant_id
     or v_to.tenant_id <> p_tenant_id
     or v_from.branch_id <> p_branch_id
     or v_to.branch_id <> p_branch_id then
    raise exception 'Transfer account context does not match.';
  end if;

  if v_from.current_balance < p_amount then
    raise exception 'Insufficient source account balance.';
  end if;

  insert into public.account_transactions (
    id,
    tenant_id,
    branch_id,
    account_id,
    related_account_id,
    transfer_group_id,
    transaction_type,
    direction,
    amount,
    description,
    transaction_at,
    created_by
  )
  values
    (
      p_out_transaction_id,
      p_tenant_id,
      p_branch_id,
      p_from_account_id,
      p_to_account_id,
      p_transfer_group_id,
      'transfer_out',
      'out',
      p_amount,
      p_description,
      coalesce(p_transaction_at, now()),
      auth.uid()
    ),
    (
      p_in_transaction_id,
      p_tenant_id,
      p_branch_id,
      p_to_account_id,
      p_from_account_id,
      p_transfer_group_id,
      'transfer_in',
      'in',
      p_amount,
      p_description,
      coalesce(p_transaction_at, now()),
      auth.uid()
    );

  update public.accounts
  set current_balance = current_balance - p_amount
  where id = p_from_account_id;

  update public.accounts
  set current_balance = current_balance + p_amount
  where id = p_to_account_id;

  return p_transfer_group_id;
end;
$$;

revoke all on function public.record_account_transfer(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text, timestamptz
) from public, anon;

grant execute on function public.record_account_transfer(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text, timestamptz
) to authenticated;
