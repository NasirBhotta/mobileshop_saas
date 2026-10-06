# SEC-17 atomic contracts: customer buy-in and POS return restock

Date: 2026-10-06. Status: source and live-metadata design. No Supabase or application behavior changed by this document.

## Why these operations need one transaction

The current customer buy-in flow independently creates/updates a product, overwrites inventory quantity, creates an IMEI unit, optionally posts an account outflow, and inserts `customer_purchases`. The POS return flow independently upserts a return, deletes/reinserts its items, creates a returned product, increments inventory, and posts a refund/credit adjustment. A retry or failure between steps can leave an orphaned record, duplicate stock or a financial mismatch. Broad direct CRUD also lets a caller invoke any one step without the others.

These flows must move as a complete operation. A partial server RPC that only protects one table would not make the workflow secure.

## Customer buy-in: `commit_customer_buyin_v2(p_buyin jsonb)`

The client submits one stable `purchase_id` and product/inventory-unit IDs. The server derives actor from `auth.uid()` and tenant from the target branch. It must ignore supplied `tenant_id`, `created_by`, `user_id`, inventory quantity and account balance.

Required transaction sequence:

1. Require active actor, active assignment for the branch, and documented permissions for product creation/update and IMEI management. Add a dedicated buy-in permission before production; do not silently reuse a broad direct-write grant.
2. Lock or create the product in the target branch. For an existing product, allow only explicitly selected editable fields and increment stock by one; never replace current quantity with a client snapshot.
3. Lock/check IMEI uniqueness in the tenant before creating one available `inventory_units` row.
4. Create exactly one `customer_purchases` row, tied to the product/unit/purchase id. An exact retry returns the original result; a reused purchase id or IMEI with different details fails.
5. If payment account and positive purchase price are present, validate the account tenant/branch/active state and post one idempotent account transaction. Update its balance inside this transaction.
6. Commit all records together or none. Return purchase ID, product ID, inventory-unit ID and resulting quantity.

The current client has a local-first queue. It must queue this entire payload under the stable purchase ID, rather than separately pre-syncing product, inventory unit and purchase record.

## POS return: `commit_pos_return_v2(p_return jsonb)`

The client submits one stable return ID with original sale ID, intended status, item quantities/refunds, selected restock product IDs, refund data and approval details. The server derives the actor and requires the original sale branch.

Required transaction sequence:

1. Require `pos.sale.return` for create; if approval changes are allowed, require a dedicated approval permission. Confirm original sale, branch, customer and all requested sale items belong together.
2. Lock return and original sale rows. Enforce returned quantity/refund capacity across prior approved returns; prevent a duplicate return ID from changing contents.
3. Create/update return parent and items without delete/reinsert windows.
4. For approved restocks, create or lock the returned product, then increment inventory as a delta under the same lock. A retry must not increment twice.
5. For cash/credit refund, call the existing validated ledger logic internally or incorporate its invariants in the same transaction. A return must never become approved/restocked while its required refund cannot be posted.
6. Return the final status and all stable IDs. Existing refund RPCs should become internal-only once this end-to-end route is deployed and clients no longer call them separately.

## Client migration sequence

1. Add `commit_customer_buyin_v2` and `commit_pos_return_v2` attempts first, with fallback only when the RPC is absent (`PGRST202`/function-not-found). Existing production behavior remains unchanged until staging installs the RPCs.
2. Treat authorization, validation, conflict and ledger errors as terminal. Do not fall back to raw table mutations after an installed secure RPC rejects a request.
3. Preserve local queue entries and surface terminal reconciliation errors. Do not generate a fresh ID during retries.
4. Test old and new client versions in staging. Only then remove direct writers from the new app and schedule final policy/grant cutover.

## Facts that must be confirmed from the deployed catalog before SQL is drafted

- Final live signature and body for `record_account_transaction_v2`; repository history indicates it supports idempotent source-event keys, but staged SQL must follow the deployed definition.
- IMEI uniqueness indexes and all `inventory_units` triggers/constraints.
- Approved/pending/rejected return business rules, split-payment refund behavior and restock-product lifecycle.
- Whether a return may be created by one user and approved/restored by another.
- The exact dedicated permission policy for buy-in and return approval.

No SQL draft is intentionally provided yet. Guessing any of these financial contracts would risk breaking existing accounting or giving a false security guarantee.
