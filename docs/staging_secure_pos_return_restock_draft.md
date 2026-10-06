# Staging draft: `commit_pos_return_v2`

This is deliberately a reviewed implementation specification, not executable SQL yet. The live export confirms that the existing cash/credit refund functions are individually safe, but the current application first changes return rows and stock, then calls those financial functions. A generic SQL rewrite without a real staging integration test could create a partially approved return or double restock. The staging implementation must be written and tested as one transaction alongside the actual staging schema.

## RPC input

`commit_pos_return_v2(p_return jsonb)` receives the current `SaleReturnModel.toMap()` payload: stable return ID, original sale/branch/user IDs, status, refund method/amount/payment ID, approval fields, return items with stable `restock_product_id`, and cash refund legs.

The client now tries this RPC first and falls back only when PostgREST reports that the RPC does not exist. An authorization, validation, conflict or ledger error must not fall back to direct writes.

## Required transaction body

1. Lock by return ID and fetch original sale/branch. Derive tenant and actor from the database; reject client `user_id`/`approved_by` values that do not match the permitted actor/state transition.
2. Require `pos.sale.return` for pending creation. Require `pos.return.approve` to create or transition to `approved`. Confirm active branch permission, original sale branch and each original product/item.
3. Validate each requested item quantity against original sale quantity minus quantities already in other approved/pending returns according to the documented business rule. Recalculate/refuse refund totals outside original item capacity.
4. For an exact retry, return the stored result. A changed retry fails. Never delete/reinsert existing return items.
5. Insert return parent/items. For pending returns, stop here.
6. For approved returns, lock/create each returned product using its stable restock ID, increment stock as a delta, and record a durable idempotency marker before posting money.
7. Invoke the existing cash or credit refund logic internally within the same transaction. If it fails, the return insertion/restock rolls back too. Do not separately expose an approved/restocked state before refund validation completes.
8. Return final status and result IDs. Direct writes/policies stay unchanged during the compatibility window.

## Staging acceptance cases

- Pending return saves once and only an authorized approver can transition it.
- Approved cash, credit and zero-refund returns create exactly one restock effect and proper ledger/account outcome.
- Duplicate retry does not create another return item, product, stock increment or refund.
- Over-return, cross-branch/tenant, inactive user, revoked assignment, changed retry and invalid refund allocation leave no partial state.
- A current client on a server without the RPC uses legacy flow unchanged; once the RPC exists, any secure rejection remains visible for reconciliation.
