# SEC-17: compatible direct-write removal contract

Date: 2026-10-05. Status: design and source tracing only. This is not SQL to run and does not alter the application or Supabase project.

## Objective

Remove direct `authenticated` mutation access to financial and stock tables without breaking supported mobile/desktop clients, offline queues or returns. Every protected write must pass through one server operation that uses `auth.uid()`, checks active membership, tenant, active branch assignment and the relevant action permission. The server, rather than the client, owns totals, balances and stock transitions.

## Confirmed writers and replacement boundary

| Current route | Checked-in location | Why a direct revoke breaks it | Required replacement |
| --- | --- | --- | --- |
| Normal sale | `pos_repository.dart` → `commit_pos_sale_v2` | Already uses the intended RPC; preserve its contract | Keep `commit_pos_sale_v2` as the only public sale creation path and verify its final live grants/validation |
| Missing sale parent for return | `_restoreRemoteSaleSnapshot` upserts `sales`, deletes/reinserts `sale_items` and `sale_payments` | A return can need a locally held parent that is absent remotely | Replace with one `restore_pos_sale_for_return` RPC. It must be atomic, require return permission plus original-sale branch access, perform the same sale validation/invariants as checkout, and only allow restoration when no server parent exists. A generic table upsert is not acceptable. |
| Return and restock | `_syncReturnRemote` writes return rows, creates a returned product and increments inventory | The sequence can leave a partial return or arbitrary stock change | Replace the approval/restock portion with one idempotent return RPC. It must validate original sale/item quantities, approval state, refund amount, and create/restock the returned product inside its transaction. |
| Stock adjustment | `adjustStock` writes `stock_adjustments`, then writes absolute `inventory.quantity` | A client can select any resulting stock | Replace with `adjust_inventory_stock(event)` RPC. Send immutable event id, product, signed direction/quantity, reason and note; server computes the new quantity, records the event and rejects a duplicate with different contents. |
| Product create/update/import/bulk price | `inventory_repository.dart` and `inventory_sync_engine.dart` upsert `products`, then inventory | One broad product upsert can change price, branch, stock or active status | Split into server operations: product create, product metadata edit, product price edit, product deactivate and import batch. Each accepts only allowed fields and has separate action permissions. Stock must never be accepted through product upsert. |
| Stock threshold | `updateBranchThreshold` writes inventory row with threshold | Removing all inventory writes breaks this harmless setting | Use a narrow `set_inventory_reorder_threshold` RPC; it can modify threshold only, never quantity. |
| Customer buy-in | `customer_purchase_repository.dart` ensures product/inventory before registering an IMEI purchase | Direct pre-sync can fabricate price/stock records | Make buy-in one atomic server operation that creates/reuses the product, inventory unit, purchase and inventory event after IMEI and permission validation. |

## Critical offline rule

The client keeps local mutations only as pending requests; the server remains the authority. Each queued mutation needs a stable UUID event/request ID. On retry, the server returns the original completed outcome only when the same actor and same immutable payload are supplied. A reused ID with changed contents must fail. A `42501` denial is terminal: keep it visible for reconciliation and do not mark it synced or retry forever.

Absolute `new_stock` is unsafe for offline replay because another sale or adjustment may have happened. Queue a delta/event instead. Likewise, a full product snapshot must not silently overwrite a concurrent price, branch or status change.

## Required server-side checks

1. Resolve actor only from `auth.uid()`; never trust a `user_id`, tenant id or branch id supplied by the client.
2. Reject a missing tenant, inactive/deleted user or revoked branch assignment before modifying anything.
3. Verify the target branch belongs to the actor's tenant and that the actor holds the action permission for that branch. Owner-wide access must be an explicit rule, not an accidental `NULL` bypass.
4. Lock/update stock conditionally in the same transaction as its event and financial records. A failed validation must leave no parent, child, payment, ledger or stock partial state.
5. Use a fixed `search_path` and revoke `PUBLIC` execution; grant only the intended public RPCs to `authenticated`.
6. After all supported clients use these operations, revoke direct INSERT/UPDATE/DELETE rights on `sales`, `sale_items`, `sale_payments`, `products`, `inventory` and related event tables. Recheck effective grants and every RLS policy; a second permissive policy can reopen access.

## Safe release sequence

1. Export the actual staging schema, grants, policy definitions, triggers and current function definitions. Compare them with the supplied production metadata; do not copy the isolated prototype.
2. Add and test new RPCs in staging while current direct-write routes remain available. Test each existing native client, including a queued offline mutation made before upgrade.
3. Release a client version that uses the replacement RPCs and reports terminal sync failures clearly. Retain old direct-write access only for a short, measured compatibility window.
4. Confirm telemetry shows supported clients have moved, no old queue is pending, and all authorization/financial invariants pass.
5. In a maintenance release, narrow grants and policies. Immediately run low-privilege REST tests: cross-branch sale/payment/product/stock mutation, disabled account, revoked branch, direct table write and approved RPC control.
6. Monitor failed sync, checkout, return and inventory event rates. Do not restore broad table writes as an automatic rollback; fix the failed operation or pause the affected feature while preserving its local queue.

## Acceptance matrix before production revoke

| Test | Expected result |
| --- | --- |
| Current POS checkout and retry | Exactly one sale, correct ledger/payment/items/stock; no duplicate effect |
| Return where sale exists | Return/approval/refund/restock stays atomic and idempotent |
| Return whose local parent is absent remotely | Explicit safe restore through RPC or a visible reconciliation state; never raw table writes |
| Offline product create/edit/import | Queue survives restart; valid request syncs once; conflicting/unauthorized request remains visible |
| Offline stock adjustment | Server applies a delta once; concurrent sale cannot be overwritten by client absolute quantity |
| Owner, manager, cashier, disabled user, revoked branch | Only documented role/action/branch combinations succeed |
| Direct REST table mutation | Denied for every protected table, including same-tenant other branch |
| iOS web, Android, Windows/desktop | All supported actions work on the staged backend before live cutover |

## What the isolated prototype proves—and does not

`security-review-null-tenant/sec17/prototype.sql` is an in-memory synthetic proof of the permission boundary. Its 15 checks cover direct-write denial, authorized sale/stock operations, cross-tenant/branch denial, revoked membership, retries and stock integrity. It does not contain this application's actual schema, payment mix, discounts, taxes, ledger, IMEI, product import, buy-in, return or Supabase HTTP behavior. Do not run it in Supabase.
