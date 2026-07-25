-- Reversal-only deletion semantics and branch-safe reporting.

create or replace function public.void_mobile_service_transaction(
  p_transaction_id uuid,
  p_cash_reversal_transaction_id uuid,
  p_provider_reversal_transaction_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_transaction public.mobile_service_transactions%rowtype;
begin
  if auth.uid() is null or v_tenant_id is null then
    raise exception using errcode = '42501',
      message = 'Authentication required.';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception using errcode = '22023',
      message = 'Void reason is required.';
  end if;

  select t.*
  into v_transaction
  from public.mobile_service_transactions t
  where t.id = p_transaction_id
    and t.tenant_id = v_tenant_id
  for update;

  if not found
     or not public.current_user_can_access_branch(v_transaction.branch_id)
     or not public.current_user_has_permission(
       'mobile_service.transaction.void'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  -- Idempotent retry: a completed reversal is never applied twice.
  if v_transaction.status = 'voided' then
    return p_transaction_id;
  end if;

  perform 1
  from public.accounts a
  where a.id in (
    v_transaction.cash_account_id,
    v_transaction.provider_account_id
  )
  order by a.id
  for update;

  if v_transaction.operation = 'send' then
    if (
      select a.current_balance
      from public.accounts a
      where a.id = v_transaction.cash_account_id
    ) < v_transaction.customer_cash_amount then
      raise exception using errcode = '22023',
        message = 'Insufficient cash balance to void this transaction.';
    end if;
  else
    if (
      select a.current_balance
      from public.accounts a
      where a.id = v_transaction.provider_account_id
    ) < v_transaction.service_amount then
      raise exception using errcode = '22023',
        message = 'Insufficient provider wallet balance to void this transaction.';
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
      p_cash_reversal_transaction_id, v_transaction.tenant_id,
      v_transaction.branch_id, v_transaction.cash_account_id,
      v_transaction.provider_account_id, v_transaction.id,
      'mobile_service_reversal',
      case when v_transaction.operation = 'send' then 'out' else 'in' end,
      v_transaction.customer_cash_amount,
      'Void: ' || trim(p_reason),
      'mobile_service_void', v_transaction.id::text, now(), auth.uid()
    ),
    (
      p_provider_reversal_transaction_id, v_transaction.tenant_id,
      v_transaction.branch_id, v_transaction.provider_account_id,
      v_transaction.cash_account_id, v_transaction.id,
      'mobile_service_reversal',
      case when v_transaction.operation = 'send' then 'in' else 'out' end,
      v_transaction.service_amount,
      'Void: ' || trim(p_reason),
      'mobile_service_void', v_transaction.id::text, now(), auth.uid()
    );

  if v_transaction.operation = 'send' then
    update public.accounts
    set current_balance =
      current_balance - v_transaction.customer_cash_amount
    where id = v_transaction.cash_account_id;

    update public.accounts
    set current_balance = current_balance + v_transaction.service_amount
    where id = v_transaction.provider_account_id;
  else
    update public.accounts
    set current_balance =
      current_balance + v_transaction.customer_cash_amount
    where id = v_transaction.cash_account_id;

    update public.accounts
    set current_balance = current_balance - v_transaction.service_amount
    where id = v_transaction.provider_account_id;
  end if;

  update public.mobile_service_transactions
  set status = 'voided',
      voided_at = now(),
      voided_by = auth.uid(),
      void_reason = trim(p_reason),
      cash_reversal_transaction_id = p_cash_reversal_transaction_id,
      provider_reversal_transaction_id =
        p_provider_reversal_transaction_id
  where id = v_transaction.id;

  return v_transaction.id;
end
$function$;

create or replace function public.mobile_service_report_summary(
  p_branch_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_provider_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_result jsonb;
begin
  if auth.uid() is null
     or v_tenant_id is null
     or not public.current_user_can_access_branch(p_branch_id)
     or not public.current_user_has_permission(
       'mobile_service.report.view'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  if p_from is null or p_to is null or p_to <= p_from then
    raise exception using errcode = '22023',
      message = 'Invalid report date range.';
  end if;

  select jsonb_build_object(
    'transaction_count', count(*),
    'send_count', count(*) filter (where t.operation = 'send'),
    'receive_count', count(*) filter (where t.operation = 'receive'),
    'sent_amount', coalesce(sum(t.service_amount)
      filter (where t.operation = 'send'), 0),
    'received_amount', coalesce(sum(t.service_amount)
      filter (where t.operation = 'receive'), 0),
    'customer_cash_in', coalesce(sum(t.customer_cash_amount)
      filter (where t.operation = 'send'), 0),
    'customer_cash_out', coalesce(sum(t.customer_cash_amount)
      filter (where t.operation = 'receive'), 0),
    'profit', coalesce(sum(t.profit_amount), 0)
  )
  into v_result
  from public.mobile_service_transactions t
  where t.tenant_id = v_tenant_id
    and t.branch_id = p_branch_id
    and t.status = 'completed'
    and t.transaction_at >= p_from
    and t.transaction_at < p_to
    and (p_provider_id is null or t.provider_id = p_provider_id);

  return v_result;
end
$function$;

create or replace function public.mobile_service_profit_summary(
  p_branch_id uuid,
  p_day_start timestamptz,
  p_day_end timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_result jsonb;
begin
  if auth.uid() is null
     or v_tenant_id is null
     or not public.current_user_can_access_branch(p_branch_id)
     or not (
       public.current_user_has_permission('mobile_service.report.view')
       or public.current_user_has_permission('report.business.view')
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  if p_day_start is null
     or p_day_end is null
     or p_day_end <= p_day_start then
    raise exception using errcode = '22023',
      message = 'Invalid day range.';
  end if;

  select jsonb_build_object(
    'today_profit',
      coalesce(sum(t.profit_amount) filter (
        where t.transaction_at >= p_day_start
          and t.transaction_at < p_day_end
      ), 0),
    'total_profit', coalesce(sum(t.profit_amount), 0)
  )
  into v_result
  from public.mobile_service_transactions t
  where t.tenant_id = v_tenant_id
    and t.branch_id = p_branch_id
    and t.status = 'completed';

  return v_result;
end
$function$;

revoke all on function public.void_mobile_service_transaction(
  uuid, uuid, uuid, text
) from public, anon;
revoke all on function public.mobile_service_report_summary(
  uuid, timestamptz, timestamptz, uuid
) from public, anon;
revoke all on function public.mobile_service_profit_summary(
  uuid, timestamptz, timestamptz
) from public, anon;

grant execute on function public.void_mobile_service_transaction(
  uuid, uuid, uuid, text
) to authenticated;
grant execute on function public.mobile_service_report_summary(
  uuid, timestamptz, timestamptz, uuid
) to authenticated;
grant execute on function public.mobile_service_profit_summary(
  uuid, timestamptz, timestamptz
) to authenticated;
