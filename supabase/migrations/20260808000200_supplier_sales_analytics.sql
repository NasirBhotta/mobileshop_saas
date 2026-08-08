-- Read-only, server-aggregated supplier sales analytics. Operational POS,
-- inventory, dashboard, reporting and accounting functions remain untouched.

create index if not exists idx_sales_branch_status_created_at
  on public.sales(branch_id, status, created_at desc);
create index if not exists idx_sale_items_product_sale
  on public.sale_items(product_id, sale_id);
create index if not exists idx_sale_return_items_sale_product
  on public.sale_return_items(original_sale_id, product_id);

create or replace function public.supplier_sales_summary(
  p_supplier_id uuid,
  p_branch_id uuid,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null
)
returns table (
  linked_product_count bigint,
  shared_product_count bigint,
  sales_count bigint,
  units_sold bigint,
  sales_revenue numeric,
  cost_of_sales numeric,
  gross_profit numeric,
  profit_margin numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  with supplier_links as (
    select sp.product_id, counts.supplier_count
    from public.supplier_products sp
    join (
      select product_id, count(distinct supplier_id) as supplier_count
      from public.supplier_products group by product_id
    ) counts on counts.product_id = sp.product_id
    join public.products p on p.id = sp.product_id
    where sp.supplier_id = p_supplier_id
      and p.branch_id = p_branch_id
      and p.is_active = true
  ),
  sale_lines as (
    select s.id as sale_id, si.product_id,
           sum(si.quantity)::bigint as sold_quantity,
           sum(si.line_total)::numeric as revenue,
           sum(coalesce(si.cogs_total, si.unit_cost_at_sale * si.quantity, 0))::numeric as cost
    from public.sales s
    join public.sale_items si on si.sale_id = s.id
    where s.branch_id = p_branch_id
      and s.status = 'completed'
      and (p_date_from is null or s.created_at >= p_date_from)
      and (p_date_to is null or s.created_at < p_date_to)
    group by s.id, si.product_id
  ),
  returned as (
    select sri.original_sale_id as sale_id, sri.product_id,
           sum(sri.quantity)::bigint as returned_quantity,
           sum(sri.refund_amount)::numeric as refund
    from public.sale_return_items sri
    join public.sale_returns sr on sr.id = sri.return_id
    where sr.branch_id = p_branch_id and sr.status = 'approved'
    group by sri.original_sale_id, sri.product_id
  ),
  net as (
    select sl.sale_id, sl.product_id,
           greatest(sl.sold_quantity - coalesce(r.returned_quantity, 0), 0)::bigint as quantity,
           (sl.revenue - coalesce(r.refund, 0))::numeric as revenue,
           case when sl.sold_quantity = 0 then 0
             else sl.cost * greatest(sl.sold_quantity - coalesce(r.returned_quantity, 0), 0) / sl.sold_quantity
           end::numeric as cost
    from sale_lines sl
    left join returned r on r.sale_id = sl.sale_id and r.product_id = sl.product_id
  ),
  eligible_net as (
    select n.* from net n
    join supplier_links link on link.product_id = n.product_id
    where link.supplier_count = 1
  ),
  totals as (
    select count(distinct sale_id)::bigint as sales_count,
           coalesce(sum(quantity), 0)::bigint as units_sold,
           coalesce(sum(revenue), 0)::numeric as revenue,
           coalesce(sum(cost), 0)::numeric as cost
    from eligible_net
  )
  select
    (select count(*) from supplier_links)::bigint,
    (select count(*) from supplier_links where supplier_count > 1)::bigint,
    totals.sales_count,
    totals.units_sold,
    totals.revenue,
    totals.cost,
    (totals.revenue - totals.cost)::numeric,
    case when totals.revenue = 0 then 0
      else ((totals.revenue - totals.cost) / totals.revenue * 100)::numeric
    end
  from totals
  where public.current_user_can_access_branch(p_branch_id)
    and exists (
      select 1 from public.suppliers supplier
      where supplier.id = p_supplier_id
        and supplier.branch_id = p_branch_id
        and supplier.tenant_id = public.current_user_tenant_id()
    );
$$;

create or replace function public.supplier_product_sales_page(
  p_supplier_id uuid,
  p_branch_id uuid,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null,
  p_search text default null,
  p_profit_filter text default 'all',
  p_sort text default 'revenue_desc',
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  product_id uuid,
  product_name text,
  sku text,
  stock integer,
  units_sold bigint,
  sales_revenue numeric,
  cost_of_sales numeric,
  gross_profit numeric,
  profit_margin numeric,
  is_shared boolean,
  total_count bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with supplier_links as (
    select sp.product_id, counts.supplier_count
    from public.supplier_products sp
    join (
      select product_id, count(distinct supplier_id) as supplier_count
      from public.supplier_products group by product_id
    ) counts on counts.product_id = sp.product_id
    join public.products product on product.id = sp.product_id
    where sp.supplier_id = p_supplier_id
      and product.branch_id = p_branch_id
      and product.is_active = true
  ),
  sale_lines as (
    select s.id as sale_id, si.product_id,
           sum(si.quantity)::bigint as sold_quantity,
           sum(si.line_total)::numeric as revenue,
           sum(coalesce(si.cogs_total, si.unit_cost_at_sale * si.quantity, 0))::numeric as cost
    from public.sales s
    join public.sale_items si on si.sale_id = s.id
    where s.branch_id = p_branch_id and s.status = 'completed'
      and (p_date_from is null or s.created_at >= p_date_from)
      and (p_date_to is null or s.created_at < p_date_to)
    group by s.id, si.product_id
  ),
  returned as (
    select sri.original_sale_id as sale_id, sri.product_id,
           sum(sri.quantity)::bigint as returned_quantity,
           sum(sri.refund_amount)::numeric as refund
    from public.sale_return_items sri
    join public.sale_returns sr on sr.id = sri.return_id
    where sr.branch_id = p_branch_id and sr.status = 'approved'
    group by sri.original_sale_id, sri.product_id
  ),
  product_totals as (
    select sl.product_id,
           sum(greatest(sl.sold_quantity - coalesce(r.returned_quantity, 0), 0))::bigint as quantity,
           sum(sl.revenue - coalesce(r.refund, 0))::numeric as revenue,
           sum(case when sl.sold_quantity = 0 then 0
             else sl.cost * greatest(sl.sold_quantity - coalesce(r.returned_quantity, 0), 0) / sl.sold_quantity
           end)::numeric as cost
    from sale_lines sl
    left join returned r on r.sale_id = sl.sale_id and r.product_id = sl.product_id
    group by sl.product_id
  ),
  rows as (
    select p.id, p.name, p.sku, coalesce(i.quantity, 0)::integer as stock,
      case when link.supplier_count = 1 then coalesce(pt.quantity, 0) else 0 end::bigint as units,
      case when link.supplier_count = 1 then coalesce(pt.revenue, 0) else 0 end::numeric as revenue,
      case when link.supplier_count = 1 then coalesce(pt.cost, 0) else 0 end::numeric as cost,
      link.supplier_count > 1 as shared
    from supplier_links link
    join public.products p on p.id = link.product_id
    left join public.inventory i on i.product_id = p.id and i.branch_id = p_branch_id
    left join product_totals pt on pt.product_id = p.id
    where nullif(trim(coalesce(p_search, '')), '') is null
       or p.name ilike '%' || trim(p_search) || '%'
       or coalesce(p.sku, '') ilike '%' || trim(p_search) || '%'
       or coalesce(p.barcode, '') ilike '%' || trim(p_search) || '%'
  ),
  filtered as (
    select * from rows
    where p_profit_filter = 'all'
       or (p_profit_filter = 'profit' and revenue - cost > 0)
       or (p_profit_filter = 'loss' and revenue - cost < 0)
       or (p_profit_filter = 'unsold' and units = 0)
  )
  select id, name, sku, stock, units, revenue, cost,
    (revenue - cost)::numeric,
    case when revenue = 0 then 0 else ((revenue - cost) / revenue * 100)::numeric end,
    shared,
    count(*) over ()::bigint
  from filtered
  where public.current_user_can_access_branch(p_branch_id)
    and exists (
      select 1 from public.suppliers supplier
      where supplier.id = p_supplier_id and supplier.branch_id = p_branch_id
        and supplier.tenant_id = public.current_user_tenant_id()
    )
  order by
    case when p_sort = 'revenue_desc' then revenue end desc,
    case when p_sort = 'units_desc' then units end desc,
    case when p_sort = 'profit_desc' then revenue - cost end desc,
    case when p_sort = 'profit_asc' then revenue - cost end asc,
    case when p_sort = 'name_asc' then name end asc,
    name asc
  limit least(greatest(coalesce(p_limit, 50), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.supplier_sales_summary(uuid, uuid, timestamptz, timestamptz)
  from public, anon;
revoke all on function public.supplier_product_sales_page(uuid, uuid, timestamptz, timestamptz, text, text, text, integer, integer)
  from public, anon;
grant execute on function public.supplier_sales_summary(uuid, uuid, timestamptz, timestamptz)
  to authenticated, service_role;
grant execute on function public.supplier_product_sales_page(uuid, uuid, timestamptz, timestamptz, text, text, text, integer, integer)
  to authenticated, service_role;
