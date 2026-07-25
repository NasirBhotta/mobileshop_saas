-- Enable Mobile Services dashboard refreshes and make POS sale retries
-- compatible with installations that still have legacy text identifier
-- columns. UUID values remain validated at the RPC boundary.

do $block$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'mobile_service_transactions'
  ) then
    alter publication supabase_realtime
      add table public.mobile_service_transactions;
  end if;
end
$block$;

create or replace function public.commit_pos_sale(p_sale jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_sale_id uuid := (p_sale->>'id')::uuid;
  v_branch_id uuid := (p_sale->>'branch_id')::uuid;
  v_customer_id uuid := nullif(p_sale->>'customer_id', '')::uuid;
  v_sale_user_id uuid := (p_sale->>'user_id')::uuid;
  sale_total numeric := (p_sale->>'total')::numeric;
  payment_total numeric;
  credit_total numeric;
  item record;
begin
  if v_sale_id is null or v_branch_id is null or v_sale_user_id is null then
    raise exception using errcode = '22023',
      message = 'Sale identity is incomplete.';
  end if;

  if v_sale_user_id <> auth.uid() or not exists (
    select 1
    from public.users u
    join public.branches b
      on b.tenant_id::text = u.tenant_id::text
    where u.id::text = auth.uid()::text
      and b.id::text = v_branch_id::text
  ) then
    raise exception using errcode = '42501',
      message = 'Sale branch is not available to this user.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_sale_id::text, 0));

  if exists (
    select 1 from public.sales s where s.id::text = v_sale_id::text
  ) then
    if not exists (
      select 1
      from public.sales s
      where s.id::text = v_sale_id::text
        and s.branch_id::text = v_branch_id::text
        and s.user_id::text = v_sale_user_id::text
    ) then
      raise exception using errcode = '23505',
        message = 'Sale id is already used by another sale.';
    end if;
    return false;
  end if;

  if jsonb_typeof(p_sale->'sale_items') <> 'array'
     or jsonb_array_length(p_sale->'sale_items') = 0 then
    raise exception using errcode = '22023',
      message = 'Sale must contain at least one item.';
  end if;

  select
    coalesce(sum((payment->>'amount')::numeric), 0),
    coalesce(
      sum((payment->>'amount')::numeric)
        filter (where lower(payment->>'method') = 'credit'),
      0
    )
  into payment_total, credit_total
  from jsonb_array_elements(
    coalesce(p_sale->'sale_payments', '[]'::jsonb)
  ) payment;

  if abs(payment_total - sale_total) > 0.01 then
    raise exception using errcode = '22023',
      message = 'Payment total does not match sale total.';
  end if;

  if credit_total > 0 and (
    v_customer_id is null or not exists (
      select 1
      from public.customers c
      join public.branches sale_branch
        on sale_branch.id::text = v_branch_id::text
       and sale_branch.tenant_id::text = c.tenant_id::text
      where c.id::text = v_customer_id::text
    )
  ) then
    raise exception using errcode = '22023',
      message = 'A valid tenant customer is required for credit sales.';
  end if;

  for item in
    select
      (value->>'product_id')::uuid as product_id,
      sum((value->>'quantity')::integer) as quantity
    from jsonb_array_elements(p_sale->'sale_items')
    group by (value->>'product_id')::uuid
    order by (value->>'product_id')::uuid
  loop
    if item.quantity <= 0 then
      raise exception using errcode = '22023',
        message = 'Sale item quantity must be positive.';
    end if;

    perform 1
    from public.inventory i
    where i.branch_id::text = v_branch_id::text
      and i.product_id::text = item.product_id::text
    for update;

    if not found or not exists (
      select 1
      from public.inventory i
      where i.branch_id::text = v_branch_id::text
        and i.product_id::text = item.product_id::text
        and i.quantity >= item.quantity
    ) then
      raise exception using errcode = '23514',
        message = 'Insufficient inventory for sale.';
    end if;
  end loop;

  insert into public.sales (
    id, branch_id, customer_id, user_id, status, subtotal,
    discount_amount, tax_amount, total, notes, created_at
  )
  values (
    v_sale_id, v_branch_id, v_customer_id, v_sale_user_id,
    coalesce(nullif(p_sale->>'status', ''), 'completed'),
    (p_sale->>'subtotal')::numeric,
    (p_sale->>'discount_amount')::numeric,
    (p_sale->>'tax_amount')::numeric,
    sale_total,
    nullif(p_sale->>'notes', ''),
    coalesce((p_sale->>'created_at')::timestamptz, now())
  );

  insert into public.sale_items (
    sale_id, product_id, product_name, product_sku, quantity,
    unit_price, unit_cost_at_sale, discount_amount, tax_rate,
    cogs_total, line_total
  )
  select
    v_sale_id,
    (value->>'product_id')::uuid,
    value->>'product_name',
    nullif(value->>'product_sku', ''),
    (value->>'quantity')::integer,
    (value->>'unit_price')::numeric,
    nullif(value->>'unit_cost_at_sale', '')::numeric,
    coalesce((value->>'discount_amount')::numeric, 0),
    coalesce((value->>'tax_rate')::numeric, 0),
    nullif(value->>'cogs_total', '')::numeric,
    (value->>'line_total')::numeric
  from jsonb_array_elements(p_sale->'sale_items');

  insert into public.sale_payments (sale_id, method, amount)
  select
    v_sale_id,
    value->>'method',
    (value->>'amount')::numeric
  from jsonb_array_elements(
    coalesce(p_sale->'sale_payments', '[]'::jsonb)
  );

  for item in
    select
      (value->>'product_id')::uuid as product_id,
      sum((value->>'quantity')::integer) as quantity
    from jsonb_array_elements(p_sale->'sale_items')
    group by (value->>'product_id')::uuid
  loop
    update public.inventory
    set quantity = quantity - item.quantity,
        updated_at = now()
    where inventory.branch_id::text = v_branch_id::text
      and inventory.product_id::text = item.product_id::text;
  end loop;

  if credit_total > 0 then
    update public.customers
    set outstanding_balance =
      coalesce(outstanding_balance, 0) + credit_total
    where customers.id::text = v_customer_id::text;
  end if;

  return true;
end
$function$;

revoke all on function public.commit_pos_sale(jsonb) from public, anon;
grant execute on function public.commit_pos_sale(jsonb)
to authenticated, service_role;
