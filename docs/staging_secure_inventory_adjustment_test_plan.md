# Staging test plan: secure stock adjustment RPC

This plan applies only after the staging draft is reviewed and installed in a separate Supabase project. It must not be run in production.

## Why this is additive

The draft adds a nullable `result_quantity` column, one permission, and one new RPC. It leaves existing grants, RLS policies and client calls untouched. Existing installed applications therefore continue their current behavior until a separately tested client release begins calling `adjust_inventory_stock_v2`.

## Required checks

1. Cashier with active branch assignment and `inventory.stock.adjust` can submit a positive stock-in and stock-out for their assigned branch.
2. The same cashier cannot call the RPC for another branch, another tenant, an inactive/deleted account, or a revoked assignment.
3. A stock-out below zero fails and changes neither inventory nor `stock_adjustments`.
4. A negative-stock override is denied to cashier/manager unless the tenant has explicitly granted `inventory.stock.override`; owner role succeeds only when its active branch policy permits it.
5. Same UUID and same payload returns the original `result_quantity` with `duplicate: true`; same UUID with changed payload fails.
6. Two concurrent stock-outs cannot overwrite each other: the final quantity equals the ordered deltas, and a non-override request cannot silently make stock negative.
7. Existing product creation/import, threshold edit, POS sale, return, buy-in and offline queue flows still work because their current direct-write routes have not yet changed.
8. Call the old direct inventory route in staging as a baseline control. It will still succeed by design until the client migration and final grant/policy cutover.

## Client migration afterwards

Replace the two-step client sequence—insert `stock_adjustments`, then upsert absolute `inventory.quantity`—with the one RPC. The offline queue must retain the same adjustment UUID and submit the original delta payload. A `42501` response is terminal and needs a visible reconciliation state; it must never be silently retried as a network failure.
