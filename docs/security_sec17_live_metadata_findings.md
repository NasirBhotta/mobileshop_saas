# SEC-17 live metadata findings

Date: 2026-10-05. Evidence: user-provided output from the single read-only catalog export. No application or Supabase change was made.

## Confirmed live state

All inspected affected tables have RLS enabled, but none force RLS. `authenticated` has direct `SELECT`, `INSERT`, `UPDATE` and `DELETE` on `sales`, `sale_items`, `sale_payments`, `products`, `inventory`, `stock_adjustments`, `sale_returns`, `sale_return_items` and `inventory_units`. The same broad access exists for `customer_purchases`, along with additional database privileges.

The applicable RLS policies are permissive and tenant-wide. For example, the policies for `sales`, `inventory` and `stock_adjustments` allow every branch in the actor's tenant; the policies for `products`, `sale_items` and `sale_payments` likewise use tenant membership. They do not call the active-branch/action helper. Therefore a same-tenant authenticated user can still use a direct API request to write financial or stock records outside the intended UI flow. This confirms the isolated SEC-17 reproduction is applicable to the live authorization design, although no live exploit request was made.

The following public RPC boundary is healthy but incomplete:

- `commit_pos_sale_v2(jsonb)` is `SECURITY DEFINER`, has fixed `search_path`, is executable by `authenticated`, and calls amount validation before the internal implementation.
- The internal `commit_pos_sale` and `commit_pos_sale_v2_unvalidated` are not executable by `authenticated`.
- Cash and credit return ledger RPCs are `SECURITY DEFINER`, use branch-permission checks and are executable by `authenticated`.

Those RPCs cannot protect a request that writes the underlying tables directly.

## Authorization helper status

`current_user_has_branch_permission` already contains the active/deleted actor guard, `NULL` tenant guard and an active branch-role-assignment check. This matches the earlier SEC-03/04/16 candidate direction for calls that use this helper.

Two helpers still have weaker behavior:

- `current_user_tenant_id()` returns a tenant for any matching user row without checking `is_active` or `deleted_at`. It is executable by `PUBLIC`, including `anon`.
- `current_user_can_access_branch(branch_id)` checks the selected `users.branch_id`, but does not check active role assignment or current action permission. It is executable by `authenticated`.

Whether these two helpers are exploitable in a current path requires a complete caller inventory; they should not be changed independently until that is reviewed. The direct table-write issue is independently confirmed by the actual grants and policies.

## Compatibility facts from the live schema

- `inventory` has a unique `(branch_id, product_id)` row and stores both `quantity` and `reorder_threshold`; a future stock RPC must preserve the distinction.
- `sale_items` has triggers that calculate/copy cost and line totals, so a replacement cannot assume client-supplied line values are authoritative.
- Sale payment account/ledger foreign keys and sale-return foreign keys exist. A return/recovery migration must preserve these relations atomically.
- `stock_adjustments` has type and positive-quantity constraints but no database constraint tying its event to the resulting inventory quantity.
- The supplied role matrix grants Cashier, Manager and Owner the listed product create/update/delete, stock-adjust and POS sale/return permissions. This is an authorization policy choice. The secure replacement must enforce it at the server/branch boundary; it must not assume only managers may adjust stock.

## Safe next implementation order

1. Do **not** revoke table privileges or alter live RLS yet. Existing mobile/desktop flows still make direct writes.
2. Draft staging-only RPCs using the verified column/trigger/constraint contracts: stock adjustment first, then a field-scoped product mutation boundary, then return recovery/restock and buy-in.
3. Update the client to use each new RPC while preserving its queue IDs and clear terminal-error handling. Test current Android/Windows/iOS/web builds and existing offline queues against a separate staging project.
4. Re-export staging grants/policies and perform direct low-privilege API tests. Only after all supported clients use the new operations should direct write grants/policies be narrowed in a scheduled production change.

## Current restriction

This document is evidence and design only. No SQL from the isolated prototype or from a future staging draft should be run against production until a concrete reviewed migration, client compatibility proof and explicit production rollout decision exist.
