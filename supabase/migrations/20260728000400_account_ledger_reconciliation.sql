-- Read-only account-ledger reconciliation diagnostics.
-- This migration never changes balances or historical ledger rows.

create or replace function public.account_ledger_reconciliation(
  p_tenant_id uuid,
  p_branch_id uuid
)
returns table (
  account_id uuid,
  account_name text,
  opening_balance numeric,
  stored_balance numeric,
  expected_balance numeric,
  difference numeric,
  ledger_entry_count bigint,
  is_reconciled boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.current_user_has_branch_permission(
    p_tenant_id,
    p_branch_id,
    'account.account.view'
  ) or not public.current_user_has_branch_permission(
    p_tenant_id,
    p_branch_id,
    'account.transaction.view'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Account reconciliation permission is required.';
  end if;

  return query
  with calculated as (
    select
      account.id as account_id,
      account.name as account_name,
      account.opening_balance,
      account.current_balance as stored_balance,
      account.opening_balance + coalesce(
        sum(
          case
            -- opening_balance is already represented by accounts.opening_balance.
            when ledger.transaction_type = 'opening_balance' then 0
            when ledger.direction = 'in' then ledger.amount
            when ledger.direction = 'out' then -ledger.amount
            else 0
          end
        ),
        0
      ) as expected_balance,
      count(ledger.id) as ledger_entry_count
    from public.accounts account
    left join public.account_transactions ledger
      on ledger.account_id = account.id
     and ledger.tenant_id = account.tenant_id
     and ledger.branch_id = account.branch_id
    where account.tenant_id = p_tenant_id
      and account.branch_id = p_branch_id
    group by
      account.id,
      account.name,
      account.opening_balance,
      account.current_balance
  )
  select
    calculated.account_id,
    calculated.account_name,
    calculated.opening_balance,
    calculated.stored_balance,
    calculated.expected_balance,
    calculated.stored_balance - calculated.expected_balance as difference,
    calculated.ledger_entry_count,
    abs(calculated.stored_balance - calculated.expected_balance) <= 0.005
      as is_reconciled
  from calculated
  order by calculated.account_name;
end;
$$;

create or replace function public.account_ledger_integrity_summary(
  p_tenant_id uuid,
  p_branch_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.current_user_has_branch_permission(
    p_tenant_id,
    p_branch_id,
    'account.account.view'
  ) or not public.current_user_has_branch_permission(
    p_tenant_id,
    p_branch_id,
    'account.transaction.view'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Account reconciliation permission is required.';
  end if;

  with
  calculated_balances as (
    select
      account.id,
      account.current_balance as stored_balance,
      account.opening_balance + coalesce(
        sum(
          case
            when ledger.transaction_type = 'opening_balance' then 0
            when ledger.direction = 'in' then ledger.amount
            when ledger.direction = 'out' then -ledger.amount
            else 0
          end
        ),
        0
      ) as expected_balance
    from public.accounts account
    left join public.account_transactions ledger
      on ledger.account_id = account.id
     and ledger.tenant_id = account.tenant_id
     and ledger.branch_id = account.branch_id
    where account.tenant_id = p_tenant_id
      and account.branch_id = p_branch_id
    group by account.id, account.current_balance, account.opening_balance
  ),
  transfer_groups as (
    select
      ledger.transfer_group_id,
      count(*) as leg_count,
      count(*) filter (
        where ledger.transaction_type = 'transfer_out'
          and ledger.direction = 'out'
      ) as out_count,
      count(*) filter (
        where ledger.transaction_type = 'transfer_in'
          and ledger.direction = 'in'
      ) as in_count,
      coalesce(sum(ledger.amount) filter (
        where ledger.transaction_type = 'transfer_out'
          and ledger.direction = 'out'
      ), 0) as out_amount,
      coalesce(sum(ledger.amount) filter (
        where ledger.transaction_type = 'transfer_in'
          and ledger.direction = 'in'
      ), 0) as in_amount
    from public.account_transactions ledger
    where ledger.tenant_id = p_tenant_id
      and ledger.branch_id = p_branch_id
      and ledger.transfer_group_id is not null
    group by ledger.transfer_group_id
  ),
  duplicate_source_events as (
    select ledger.source_event_key
    from public.account_transactions ledger
    where ledger.tenant_id = p_tenant_id
      and ledger.branch_id = p_branch_id
      and ledger.source_event_key is not null
    group by ledger.source_event_key
    having count(*) > 1
  ),
  cross_context_transactions as (
    select ledger.id
    from public.account_transactions ledger
    left join public.accounts account on account.id = ledger.account_id
    where ledger.tenant_id = p_tenant_id
      and ledger.branch_id = p_branch_id
      and (
        account.id is null
        or account.tenant_id <> ledger.tenant_id
        or account.branch_id <> ledger.branch_id
      )
  ),
  invalid_reversals as (
    select reversal.id
    from public.account_transactions reversal
    left join public.account_transactions original
      on original.id = reversal.reversal_of_transaction_id
    where reversal.tenant_id = p_tenant_id
      and reversal.branch_id = p_branch_id
      and reversal.reversal_of_transaction_id is not null
      and (
        original.id is null
        or original.id = reversal.id
        or original.tenant_id <> reversal.tenant_id
        or original.branch_id <> reversal.branch_id
        or original.account_id <> reversal.account_id
        or original.amount <> reversal.amount
        or original.direction = reversal.direction
        or original.reversal_of_transaction_id is not null
      )
  )
  select jsonb_build_object(
    'balance_discrepancies', (
      select count(*)
      from calculated_balances balance
      where abs(balance.stored_balance - balance.expected_balance) > 0.005
    ),
    'incomplete_transfer_groups', (
      select count(*)
      from transfer_groups transfer
      where transfer.leg_count <> 2
        or transfer.out_count <> 1
        or transfer.in_count <> 1
        or transfer.out_amount <> transfer.in_amount
    ),
    'duplicate_source_events', (
      select count(*) from duplicate_source_events
    ),
    'cross_context_transactions', (
      select count(*) from cross_context_transactions
    ),
    'invalid_reversals', (
      select count(*) from invalid_reversals
    ),
    'is_healthy', (
      not exists (
        select 1
        from calculated_balances balance
        where abs(balance.stored_balance - balance.expected_balance) > 0.005
      )
      and not exists (
        select 1
        from transfer_groups transfer
        where transfer.leg_count <> 2
          or transfer.out_count <> 1
          or transfer.in_count <> 1
          or transfer.out_amount <> transfer.in_amount
      )
      and not exists (select 1 from duplicate_source_events)
      and not exists (select 1 from cross_context_transactions)
      and not exists (select 1 from invalid_reversals)
    ),
    'checked_at', now()
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.account_ledger_reconciliation(
  uuid, uuid
) from public, anon;
revoke all on function public.account_ledger_integrity_summary(
  uuid, uuid
) from public, anon;

grant execute on function public.account_ledger_reconciliation(
  uuid, uuid
) to authenticated;
grant execute on function public.account_ledger_integrity_summary(
  uuid, uuid
) to authenticated;
