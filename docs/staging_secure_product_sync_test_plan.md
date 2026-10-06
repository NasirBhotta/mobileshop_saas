# Staging test plan: secure product sync RPC

The draft is additive only. Current clients continue to use direct writes until a client has this compatibility update and staging provides `upsert_inventory_product_v2`.

Test these cases in a separate staging project:

1. Authorized user creates a product and its initial inventory row once.
2. Authorized user updates product details and price for their branch; the cached `stock` field does not overwrite current inventory quantity.
3. A user cannot create/update/deactivate a product in another branch or tenant, including by changing JSON `tenant_id`.
4. Product deactivation needs `inventory.product.delete`; normal edits need `inventory.product.update`.
5. Existing product with missing inventory receives a zero-quantity row and the requested reorder threshold.
6. Direct legacy writes still work during the transition; this is expected until the final cutover.
7. An old server with no RPC triggers the narrow client fallback; an authorization or validation failure from an installed RPC does not fall back.
