-- Read-only customer activity. Invoker security retains table RLS; explicit
-- branch permissions prevent customer access from implying financial access.
begin;
create index if not exists sales_customer_activity_idx on public.sales(customer_id, branch_id, created_at desc, id);
create index if not exists repairs_customer_activity_idx on public.repair_tickets(customer_id, branch_id, created_at desc, id);
create index if not exists repair_payments_ticket_activity_idx on public.repair_payments(ticket_id, received_at);

create or replace function public.customer_activity_v1(
  p_customer_id uuid, p_branch_id uuid, p_from timestamptz default null,
  p_to timestamptz default null, p_offset integer default 0, p_limit integer default 25
) returns jsonb language plpgsql security invoker
set search_path = public, pg_temp as $function$
declare v_result jsonb; v_tenant uuid := public.current_user_tenant_id();
begin
  if not exists(select 1 from public.customers where id = p_customer_id and tenant_id = v_tenant)
    or not exists(select 1 from public.branches where id = p_branch_id and tenant_id = v_tenant)
    or public.current_user_has_branch_permission(v_tenant,p_branch_id,'customer.customer.view') is not true
    or public.current_user_has_branch_permission(v_tenant,p_branch_id,'customer.credit.view') is not true
    or public.current_user_has_branch_permission(v_tenant,p_branch_id,'pos.sale.view') is not true
    or public.current_user_has_branch_permission(v_tenant,p_branch_id,'repair.ticket.view') is not true then
    raise exception using errcode = '42501', message = 'Customer financial history access denied.';
  end if;
  if p_offset < 0 or p_limit < 1 or p_limit > 100 or (p_from is not null and p_to <= p_from) then
    raise exception 'Invalid activity range.';
  end if;
  with sales_scope as (
    select s.* from public.sales s where s.customer_id=p_customer_id and s.branch_id=p_branch_id and s.status <> 'held'
  ), repairs_scope as (
    select r.* from public.repair_tickets r where r.customer_id=p_customer_id and r.branch_id=p_branch_id and r.tenant_id=v_tenant
  ), activity as (
    select 'sale'::text kind, s.id, s.created_at, s.status,
      s.total amount, coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id and sp.method <> 'credit'),0) paid,
      (select string_agg(si.product_name || ' ×' || si.quantity::text || ' @ ' || si.unit_price::text, ', ')
       from public.sale_items si where si.sale_id=s.id) description,
      s.id::text reference,
      (s.status='completed') active,
      true printable
    from sales_scope s
    union all
    select 'repair',r.id,r.created_at,r.status,coalesce(r.customer_charge,r.total_cost,0),
      coalesce((select sum(rp.amount) from public.repair_payments rp where rp.ticket_id=r.id),0)
        - coalesce((select sum(rf.amount) from public.repair_payment_refunds rf where rf.ticket_id=r.id),0),
      r.device_brand || ' ' || r.device_model,r.ticket_no,
      r.status <> 'cancelled',r.ticket_no is not null
    from repairs_scope r
  ), filtered as (
    select * from activity where (p_from is null or created_at >= p_from) and (p_to is null or created_at < p_to)
  ), page as (
    select * from filtered order by created_at desc,id desc,kind limit p_limit offset p_offset
  ), payments as (
    -- Sale payments have no separate timestamp: checkout date is authoritative.
    select sp.amount,s.created_at from sales_scope s join public.sale_payments sp on sp.sale_id=s.id
      where sp.method <> 'credit' and s.status='completed'
    union all
    select rp.amount,rp.received_at from repairs_scope r join public.repair_payments rp on rp.ticket_id=r.id
    union all
    select -rf.amount,rf.refunded_at from repairs_scope r join public.repair_payment_refunds rf on rf.ticket_id=r.id
    union all
    select cs.amount,cs.created_at from public.customer_settlements cs
      where cs.customer_id=p_customer_id and cs.branch_id=p_branch_id
  )
  select jsonb_build_object(
    'entries',coalesce((select jsonb_agg(to_jsonb(page) order by created_at desc,id desc,kind) from page),'[]'::jsonb),
    'count',(select count(*) from filtered),
    'purchases',(select count(*) from filtered where kind='sale' and active),
    'repairs',(select count(*) from filtered where kind='repair' and active),
    'visits',(select count(*) from filtered where active),
    'purchase_amount',coalesce((select sum(amount) from filtered where kind='sale' and active),0),
    'repair_amount',coalesce((select sum(amount) from filtered where kind='repair' and active),0),
    'payments',coalesce((select sum(amount) from payments where (p_from is null or created_at>=p_from) and (p_to is null or created_at<p_to)),0),
    'repair_balance',coalesce((select sum(greatest(amount-paid,0)) from activity where kind='repair' and active),0)
  ) into v_result;
  return v_result;
end $function$;
revoke all on function public.customer_activity_v1(uuid,uuid,timestamptz,timestamptz,integer,integer) from public, anon;
grant execute on function public.customer_activity_v1(uuid,uuid,timestamptz,timestamptz,integer,integer) to authenticated;
commit;
