-- Atomic Easypaisa/JazzCash send and receive transactions.

-- Extend the existing cashbook catalog with explicit, reportable service types.
do $block$
declare
  v_constraint record;
begin
  for v_constraint in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.account_transactions'::regclass
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) like '%transaction_type%'
  loop
    execute format(
      'alter table public.account_transactions drop constraint %I',
      v_constraint.conname
    );
  end loop;
end
$block$;

alter table public.account_transactions
add constraint account_transactions_transaction_type_check
check (
  transaction_type in (
    'opening_balance',
    'sale',
    'customer_payment',
    'supplier_payment',
    'expense',
    'purchase',
    'transfer_in',
    'transfer_out',
    'adjustment',
    'other',
    'mobile_service_cash',
    'mobile_service_wallet',
    'mobile_service_reversal'
  )
);

create or replace function public.calculate_mobile_service_fee(
  p_amount numeric,
  p_calculation_method text,
  p_rate_amount numeric,
  p_per_amount numeric default null,
  p_minimum_fee numeric default null,
  p_maximum_fee numeric default null
)
returns numeric
language plpgsql
immutable
set search_path = public, pg_temp
as $function$
declare
  v_fee numeric;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception using errcode = '22023',
      message = 'Amount must be greater than zero.';
  end if;

  if coalesce(p_rate_amount, 0) < 0 then
    raise exception using errcode = '22023',
      message = 'Rate cannot be negative.';
  end if;

  case p_calculation_method
    when 'full_slab' then
      if coalesce(p_per_amount, 0) <= 0 then
        raise exception using errcode = '22023',
          message = 'Per amount must be greater than zero.';
      end if;
      v_fee := ceil(p_amount / p_per_amount) * p_rate_amount;
    when 'proportional' then
      if coalesce(p_per_amount, 0) <= 0 then
        raise exception using errcode = '22023',
          message = 'Per amount must be greater than zero.';
      end if;
      v_fee := (p_amount / p_per_amount) * p_rate_amount;
    when 'fixed' then
      v_fee := p_rate_amount;
    when 'manual' then
      -- The final fee is supplied separately to the transaction RPC.
      v_fee := 0;
    else
      raise exception using errcode = '22023',
        message = 'Unsupported calculation method.';
  end case;

  if p_minimum_fee is not null then
    v_fee := greatest(v_fee, p_minimum_fee);
  end if;

  if p_maximum_fee is not null then
    v_fee := least(v_fee, p_maximum_fee);
  end if;

  return round(v_fee, 2);
end
$function$;

create or replace function public.record_mobile_service_transaction(
  p_transaction_id uuid,
  p_cash_ledger_transaction_id uuid,
  p_provider_ledger_transaction_id uuid,
  p_provider_id uuid,
  p_cash_account_id uuid,
  p_operation text,
  p_service_amount numeric,
  p_charged_fee numeric default null,
  p_phone_number text default null,
  p_reference_number text default null,
  p_description text default null,
  p_transaction_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_provider public.mobile_service_providers%rowtype;
  v_rule public.mobile_service_charge_rules%rowtype;
  v_cash public.accounts%rowtype;
  v_wallet public.accounts%rowtype;
  v_calculated_fee numeric;
  v_charged_fee numeric;
  v_customer_cash numeric;
  v_transaction_at timestamptz := coalesce(p_transaction_at, now());
begin
  if auth.uid() is null or v_tenant_id is null then
    raise exception using errcode = '42501',
      message = 'Authentication required.';
  end if;

  -- Idempotent offline retry. A matching ID can affect balances only once.
  if exists (
    select 1
    from public.mobile_service_transactions t
    where t.id = p_transaction_id
      and t.tenant_id = v_tenant_id
      and t.created_by = auth.uid()
  ) then
    return p_transaction_id;
  end if;

  if p_operation not in ('send', 'receive') then
    raise exception using errcode = '22023',
      message = 'Unsupported operation.';
  end if;

  if p_service_amount is null or p_service_amount <= 0 then
    raise exception using errcode = '22023',
      message = 'Amount must be greater than zero.';
  end if;

  select p.*
  into v_provider
  from public.mobile_service_providers p
  where p.id = p_provider_id
    and p.tenant_id = v_tenant_id
    and p.category = 'money_transfer'
    and p.is_active;

  if not found
     or not public.current_user_can_access_branch(v_provider.branch_id)
     or not public.current_user_has_permission(
       'mobile_service.transaction.create'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  select r.*
  into v_rule
  from public.mobile_service_charge_rules r
  where r.provider_id = v_provider.id
    and r.tenant_id = v_tenant_id
    and r.branch_id = v_provider.branch_id
    and r.operation = p_operation
    and r.is_active;

  if not found then
    raise exception using errcode = '22023',
      message = 'An active charge rule is required.';
  end if;

  -- Lock both balances in deterministic UUID order to avoid concurrent
  -- overspending and reduce deadlock risk.
  perform 1
  from public.accounts a
  where a.id in (p_cash_account_id, v_provider.provider_account_id)
  order by a.id
  for update;

  select a.* into v_cash
  from public.accounts a
  where a.id = p_cash_account_id
    and a.tenant_id = v_tenant_id
    and a.branch_id = v_provider.branch_id
    and a.account_type = 'cash'
    and a.is_active;

  if not found then
    raise exception using errcode = '22023',
      message = 'Select an active cash account in this branch.';
  end if;

  select a.* into v_wallet
  from public.accounts a
  where a.id = v_provider.provider_account_id
    and a.tenant_id = v_tenant_id
    and a.branch_id = v_provider.branch_id
    and a.account_type = 'mobile_wallet'
    and a.is_active;

  if not found then
    raise exception using errcode = '22023',
      message = 'Provider wallet is unavailable.';
  end if;

  v_calculated_fee := public.calculate_mobile_service_fee(
    p_service_amount,
    v_rule.calculation_method,
    v_rule.rate_amount,
    v_rule.per_amount,
    v_rule.minimum_fee,
    v_rule.maximum_fee
  );

  if v_rule.calculation_method = 'manual' and p_charged_fee is null then
    raise exception using errcode = '22023',
      message = 'Enter the service fee.';
  end if;

  v_charged_fee := round(
    coalesce(p_charged_fee, v_calculated_fee),
    2
  );

  if v_charged_fee < 0 then
    raise exception using errcode = '22023',
      message = 'Service fee cannot be negative.';
  end if;

  if p_operation = 'send' then
    v_customer_cash := round(p_service_amount + v_charged_fee, 2);
    if v_wallet.current_balance < p_service_amount then
      raise exception using errcode = '22023',
        message = 'Insufficient provider wallet balance.';
    end if;
  else
    if v_charged_fee >= p_service_amount then
      raise exception using errcode = '22023',
        message = 'Fee must be less than the received amount.';
    end if;
    v_customer_cash := round(p_service_amount - v_charged_fee, 2);
    if v_cash.current_balance < v_customer_cash then
      raise exception using errcode = '22023',
        message = 'Insufficient cash balance.';
    end if;
  end if;

  insert into public.account_transactions (
    id, tenant_id, branch_id, account_id, related_account_id,
    transfer_group_id, transaction_type, direction, amount,
    description, reference_type, reference_id, transaction_at,
    created_by
  )
  values
    (
      p_cash_ledger_transaction_id, v_tenant_id, v_provider.branch_id,
      v_cash.id, v_wallet.id, p_transaction_id,
      'mobile_service_cash',
      case when p_operation = 'send' then 'in' else 'out' end,
      v_customer_cash,
      coalesce(nullif(trim(p_description), ''), initcap(p_operation)
        || ' via ' || v_provider.name),
      'mobile_service_transaction', p_transaction_id::text,
      v_transaction_at, auth.uid()
    ),
    (
      p_provider_ledger_transaction_id, v_tenant_id,
      v_provider.branch_id, v_wallet.id, v_cash.id, p_transaction_id,
      'mobile_service_wallet',
      case when p_operation = 'send' then 'out' else 'in' end,
      p_service_amount,
      coalesce(nullif(trim(p_description), ''), initcap(p_operation)
        || ' via ' || v_provider.name),
      'mobile_service_transaction', p_transaction_id::text,
      v_transaction_at, auth.uid()
    );

  if p_operation = 'send' then
    update public.accounts
    set current_balance = current_balance + v_customer_cash
    where id = v_cash.id;

    update public.accounts
    set current_balance = current_balance - p_service_amount
    where id = v_wallet.id;
  else
    update public.accounts
    set current_balance = current_balance - v_customer_cash
    where id = v_cash.id;

    update public.accounts
    set current_balance = current_balance + p_service_amount
    where id = v_wallet.id;
  end if;

  insert into public.mobile_service_transactions (
    id, tenant_id, branch_id, provider_id, charge_rule_id,
    service_category, operation, service_amount, calculation_method,
    applied_rate, applied_per_amount, calculated_fee, charged_fee,
    customer_cash_amount, profit_amount, cash_account_id,
    provider_account_id, cash_ledger_transaction_id,
    provider_ledger_transaction_id, phone_number, reference_number,
    description, status, transaction_at, created_by
  )
  values (
    p_transaction_id, v_tenant_id, v_provider.branch_id, v_provider.id,
    v_rule.id, 'money_transfer', p_operation, round(p_service_amount, 2),
    v_rule.calculation_method, v_rule.rate_amount, v_rule.per_amount,
    v_calculated_fee, v_charged_fee, v_customer_cash, v_charged_fee,
    v_cash.id, v_wallet.id, p_cash_ledger_transaction_id,
    p_provider_ledger_transaction_id,
    nullif(trim(p_phone_number), ''),
    nullif(trim(p_reference_number), ''),
    nullif(trim(p_description), ''),
    'completed', v_transaction_at, auth.uid()
  );

  return p_transaction_id;
end
$function$;

revoke all on function public.calculate_mobile_service_fee(
  numeric, text, numeric, numeric, numeric, numeric
) from public, anon;
grant execute on function public.calculate_mobile_service_fee(
  numeric, text, numeric, numeric, numeric, numeric
) to authenticated, service_role;

revoke all on function public.record_mobile_service_transaction(
  uuid, uuid, uuid, uuid, uuid, text, numeric, numeric,
  text, text, text, timestamptz
) from public, anon;
grant execute on function public.record_mobile_service_transaction(
  uuid, uuid, uuid, uuid, uuid, text, numeric, numeric,
  text, text, text, timestamptz
) to authenticated;
