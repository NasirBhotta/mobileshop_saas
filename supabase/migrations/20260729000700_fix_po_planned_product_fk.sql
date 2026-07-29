-- `resolved_product_id` is also the reserved identity for a
-- create-on-receipt product. That product intentionally does not exist while
-- the PO is still a draft, so this column cannot have an immediate products
-- foreign key. The receipt RPC creates/validates the product atomically before
-- any inventory row references it.

alter table public.purchase_order_items
  drop constraint if exists po_items_resolved_product_id_fkey;

comment on column public.purchase_order_items.resolved_product_id is
  'Reserved product identity for create_on_receipt, or the product selected '
  'while resolving goods receipt. Validated by receive_purchase_order_goods.';
