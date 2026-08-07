-- A read-only, RLS-aware projection used only by the inventory low-stock filter.
-- security_invoker keeps the underlying products/inventory/category policies in
-- force for authenticated users.
create or replace view public.inventory_product_catalog
with (security_invoker = true)
as
select
  p.*,
  c.name as category_name,
  coalesce(c.default_reorder_threshold, 0) as category_threshold,
  coalesce(i.quantity, 0) as stock,
  coalesce(i.reorder_threshold, 0) as branch_threshold,
  coalesce(
    nullif(i.reorder_threshold, 0),
    nullif(p.reorder_threshold, 0),
    nullif(c.default_reorder_threshold, 0),
    5
  ) as effective_threshold,
  (
    coalesce(i.quantity, 0) > 0
    and coalesce(i.quantity, 0) <= coalesce(
      nullif(i.reorder_threshold, 0),
      nullif(p.reorder_threshold, 0),
      nullif(c.default_reorder_threshold, 0),
      5
    )
  ) as is_low_stock
from public.products p
left join public.inventory i
  on i.product_id = p.id
 and i.branch_id = p.branch_id
left join public.categories c on c.id = p.category_id;

revoke all on public.inventory_product_catalog from anon;
grant select on public.inventory_product_catalog to authenticated;
