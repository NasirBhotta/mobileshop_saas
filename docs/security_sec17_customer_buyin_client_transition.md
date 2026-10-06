# SEC-17 customer buy-in client transition

Date: 2026-10-06. Status: implementation contract; no production database or live client behavior is changed by this document.

## Current flow and its risk

`CustomerPurchaseRepository.createPurchase` currently performs independent remote writes for a product, inventory quantity, IMEI unit, optional account transaction and customer-purchase record. If one request succeeds and a later request fails, retrying can create an inconsistent stock or financial result. The current offline queue also retries portions of this workflow separately.

The secure route must therefore submit one stable buy-in payload to `commit_customer_buyin_v2`. It must never call the old direct writes after an installed RPC rejects authorization, validation or conflict checks.

## Compatibility states

| Server result | Client action | Why |
| --- | --- | --- |
| RPC is absent (`PGRST202`/undefined function) | Use the unchanged legacy flow. | Existing production continues to work before the staged migration exists. |
| RPC returns success | Apply local cache changes and do not issue product, inventory, IMEI, ledger or purchase table writes. | The server transaction is the only authority. |
| Device/network is unavailable | Apply local cache changes and queue one `commit_customer_buyin_v2` payload with the original purchase, product and unit IDs. | A reconnect cannot split the workflow or create new IDs. |
| RPC rejects the request | Keep the pending operation visible as failed; do not perform any direct-write fallback. | A caller cannot bypass server authorization by forcing an error. |

## Required payload

The queued and online payload contains the existing `CustomerPurchaseModel` fields plus:

```text
inventory_unit_id     stable UUID generated once
create_product        true only for a new product
```

The server derives tenant, actor and account balance. Client-supplied `tenant_id`, `created_by`, stock quantity and account balance are ignored by the RPC.

## Safe implementation order

1. Add an outcome-aware RPC adapter in `customer_purchase_repository.dart`.
2. Construct all local models and the stable payload before any remote request.
3. Gate every legacy remote write behind the explicit `RPC absent` outcome.
4. Add `commit_customer_buyin_v2` as one offline mutation type; its sync handler calls only the RPC.
5. Preserve existing mutation types for old app versions and for the RPC-absent compatibility path.
6. Test all four compatibility states against a data-less staging branch before turning on the RPC for test users.
7. Only after released clients use the RPC, prepare a separate production cutover to narrow the direct-write grants and RLS policies.

## Verified server prerequisites

The live metadata export confirms that the following exist and must be preserved by the staging draft:

- `inventory_units` has a unique `(branch_id, imei)` constraint.
- `record_account_transaction_v2` accepts a `source_event_key` and the ledger has a unique tenant/branch/source-event index.
- `current_user_has_branch_permission` rejects inactive/deleted users and revoked branch assignments.
- The permission catalog includes `inventory.product.create`, `inventory.product.update`, `inventory.imei.manage` and `account.transaction.create`.

The staging SQL draft uses these primitives. The client adapter is intentionally not merged until the branch provides the actual RPC response and failure behavior for the compatibility tests.
