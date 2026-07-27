-- Canonical cash-flow report: account ledger is the only movement source.
-- Dates are interpreted in the application's business timezone (Pakistan).

create or replace function public.get_ledger_cash_flow_report(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_cash_in numeric;
  v_cash_out numeric;
  v_in_breakdown jsonb;
  v_out_breakdown jsonb;
begin
  if p_tenant_id is null or p_date_from is null or p_date_to is null
     or p_date_to < p_date_from then
    raise exception using errcode = '22023',
      message = 'Cash-flow report context or date range is invalid.';
  end if;
  if p_branch_id is not null then
    if not public.current_user_has_branch_permission(
      p_tenant_id, p_branch_id, 'report.business.view'
    ) then
      raise exception using errcode = '42501',
        message = 'Business report permission is required.';
    end if;
  elsif not exists (
    select 1
    from public.branches branch
    where branch.tenant_id = p_tenant_id
      and public.current_user_has_branch_permission(
        p_tenant_id, branch.id, 'report.all_branches.view'
      )
  ) then
    raise exception using errcode = '42501',
      message = 'All-branch report permission is required.';
  end if;

  with movement as (
    select
      transaction.direction,
      coalesce(
        nullif(transaction.reference_type, ''),
        transaction.transaction_type
      ) as label,
      transaction.amount
    from public.account_transactions transaction
    where transaction.tenant_id = p_tenant_id
      and (p_branch_id is null or transaction.branch_id = p_branch_id)
      and transaction.transaction_type not in ('transfer_in', 'transfer_out')
      and transaction.transaction_at >=
          (p_date_from::timestamp at time zone 'Asia/Karachi')
      and transaction.transaction_at <
          ((p_date_to + 1)::timestamp at time zone 'Asia/Karachi')
  ),
  grouped as (
    select direction, label, sum(amount) as amount
    from movement
    group by direction, label
  )
  select
    coalesce(sum(amount) filter (where direction = 'in'), 0),
    coalesce(sum(amount) filter (where direction = 'out'), 0),
    coalesce(
      jsonb_agg(
        jsonb_build_object('payment_mode', label, 'amount', amount)
        order by label
      ) filter (where direction = 'in'),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object('payment_mode', label, 'amount', amount)
        order by label
      ) filter (where direction = 'out'),
      '[]'::jsonb
    )
  into v_cash_in, v_cash_out, v_in_breakdown, v_out_breakdown
  from grouped;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'branch_id', p_branch_id,
    'date_from', p_date_from,
    'date_to', p_date_to,
    'summary', jsonb_build_object(
      'cash_in', v_cash_in,
      'cash_out', v_cash_out,
      'net_cash', v_cash_in - v_cash_out
    ),
    'sales_payment_breakdown', v_in_breakdown,
    'expense_payment_breakdown', v_out_breakdown
  );
end
$function$;

revoke all on function public.get_ledger_cash_flow_report(
  uuid, uuid, date, date
) from public, anon;
grant execute on function public.get_ledger_cash_flow_report(
  uuid, uuid, date, date
) to authenticated, service_role;
