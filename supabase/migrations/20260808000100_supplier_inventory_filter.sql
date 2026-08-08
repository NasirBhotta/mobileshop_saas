-- Read-only supplier projection for the existing Inventory screen. This view
-- does not change products, stock, sales, profit or accounting data.
create or replace view public.supplier_inventory_product_catalog
with (security_invoker = true)
as
select
  catalog.*,
  link.supplier_id
from public.inventory_product_catalog catalog
join public.supplier_products link
  on link.product_id = catalog.id
 and link.tenant_id = catalog.tenant_id;

revoke all on public.supplier_inventory_product_catalog from anon;
grant select on public.supplier_inventory_product_catalog to authenticated;

