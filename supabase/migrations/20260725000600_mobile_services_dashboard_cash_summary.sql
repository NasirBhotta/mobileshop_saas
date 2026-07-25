-- Include Mobile Services cash inflow in dashboard Today/Total Cash Received.

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
    'total_profit', coalesce(sum(t.profit_amount), 0),
    'today_cash_received',
      coalesce(sum(t.customer_cash_amount) filter (
        where t.operation = 'send'
          and t.transaction_at >= p_day_start
          and t.transaction_at < p_day_end
      ), 0),
    'total_cash_received',
      coalesce(sum(t.customer_cash_amount) filter (
        where t.operation = 'send'
      ), 0)
  )
  into v_result
  from public.mobile_service_transactions t
  where t.tenant_id = v_tenant_id
    and t.branch_id = p_branch_id
    and t.status = 'completed';

  return v_result;
end
$function$;

revoke all on function public.mobile_service_profit_summary(
  uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.mobile_service_profit_summary(
  uuid, timestamptz, timestamptz
) to authenticated;
