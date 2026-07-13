ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS barcode text;

CREATE UNIQUE INDEX IF NOT EXISTS products_branch_barcode_unique
ON public.products (branch_id, lower(barcode))
WHERE barcode IS NOT NULL AND btrim(barcode) <> '';

CREATE INDEX IF NOT EXISTS products_barcode_search_idx
ON public.products (tenant_id, branch_id, is_active, lower(barcode));
