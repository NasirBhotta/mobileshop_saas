-- Inventory/product scale indexes for 100k+ product catalogs.
-- Safe to run multiple times.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_products_tenant_branch_active_name
ON public.products (tenant_id, branch_id, is_active, lower(name));

CREATE INDEX IF NOT EXISTS idx_products_tenant_branch_active_sku
ON public.products (tenant_id, branch_id, is_active, lower(sku));

CREATE INDEX IF NOT EXISTS idx_products_name_trgm
ON public.products USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_products_sku_trgm
ON public.products USING gin (sku gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_products_branch_category_active_name
ON public.products (branch_id, category_id, is_active, lower(name));

CREATE INDEX IF NOT EXISTS idx_products_branch_sale_price
ON public.products (branch_id, is_active, sale_price);

CREATE INDEX IF NOT EXISTS idx_inventory_branch_product
ON public.inventory (branch_id, product_id);

CREATE INDEX IF NOT EXISTS idx_inventory_branch_quantity
ON public.inventory (branch_id, quantity);
