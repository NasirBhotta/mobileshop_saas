# SEC-17 staging return transaction contract

Derived from the staging catalog export on 2026-10-06. This document defines
the compatibility boundary for the single staging migration that will add
`commit_pos_return_v2(jsonb)`.

## Confirmed current behavior

- The client creates both `approved` and `pending_approval` returns. A later
  manager/owner approval sends the same return ID with status `approved`.
- The runtime permission key is `pos.return.approve`, not
  `pos.sale.return.approve`. The atomic RPC must use the runtime key.
- `sale_return_items` currently does not retain `restock_product_id`,
  `restock_condition`, or `resale_price`, although the client sends them.
  The migration must add them before the server can make restocks idempotent.
- Existing refund helpers validate cash allocation and credit receivables, but
  are separate public endpoints today. The new RPC will invoke them inside its
  own transaction; their public access stays unchanged until compatibility
  cutover so old installed clients keep working.
- `record_account_transaction_v2` is still called by the Accounts feature, so
  its authenticated grant cannot be removed in this phase.

## Required state transitions

| Existing state | Requested state | Rule |
|---|---|---|
| none | `pending_approval` | Actor must have `pos.sale.return`; no stock or money movement. |
| none | `approved` | Actor must have `pos.sale.return` and `pos.return.approve`; insert, restock, and refund commit together. |
| `pending_approval` | `approved` | Approver must have both permissions; requester/original sale/refund/items stay immutable; only approval metadata and the first restock/refund may be added. |
| `approved` | same exact payload | Return stored result without a second restock or refund. |
| any | changed contents or invalid transition | Reject without changes. |

## Server-derived facts

The RPC must derive tenant and source branch from `sales` and `branches`. It
must reject a client branch that differs from the original sale. It must verify
every returned product and quantity against the original sale, counting all
non-rejected returns, and it must derive product names/SKUs/cost from the
original sale/product rather than trusting client text.

For approved returns, each stable `restock_product_id` is either created once
as a returned-product record linked by `source_product_id`, or must already be
an active product in the same tenant/branch with that source product. Inventory
is incremented under a row lock. Cash calls `post_pos_return_refund`; credit
calls `post_pos_credit_return`; any failure rolls the entire transaction back.

## Non-breaking rollout

The migration will be additive: columns, permission catalog entry, RPC and
execute grants only. It will not revoke table CRUD, replace RLS policies, or
remove existing refund RPC grants. The current Flutter fallback continues only
when the new RPC is absent; when installed, validation/authorization errors
remain terminal and cannot fall back to direct writes.
