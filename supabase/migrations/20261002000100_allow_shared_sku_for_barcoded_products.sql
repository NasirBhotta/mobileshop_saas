-- SKU is also used for shared model/specification labels in existing offline data.
-- Product IDs remain authoritative; nonblank barcodes remain unique per branch.
-- Keep SKU uniqueness for products that have no barcode. Never rewrite stored data.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
LOCK TABLE public.products IN ACCESS EXCLUSIVE MODE;

-- Build replacement protection before removing the old constraint. Fail without
-- changing anything if existing unbarcoded duplicates or barcode duplicates exist.
CREATE UNIQUE INDEX IF NOT EXISTS products_branch_unbarcoded_sku_unique
ON public.products (branch_id, sku)
WHERE barcode IS NULL OR btrim(barcode) = '';

CREATE UNIQUE INDEX IF NOT EXISTS products_branch_barcode_unique
ON public.products (branch_id, lower(barcode))
WHERE barcode IS NOT NULL AND btrim(barcode) <> '';

-- No CASCADE: any dependent foreign key must block this migration for review.
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_branch_id_sku_key;
DROP INDEX IF EXISTS public.products_branch_id_sku_key;
COMMIT;
