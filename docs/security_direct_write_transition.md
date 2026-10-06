# Direct sales and inventory authorization: transition design

Date: 2026-10-05. Status: source/export analysis, isolated reproduction and isolated SQL design prototype only. No application change or deployment.

## What is confirmed

The supplied database export gives `authenticated` CRUD privileges and one permissive tenant-wide `FOR ALL` policy each on `sales`, `sale_items`, `sale_payments`, `products` and `inventory`. The policies do not check assigned branch or current action permission. The checked-in frontend's branch filters and feature checks are bypassable by direct API requests.

An [isolated PostgreSQL reproduction](../../security-review-null-tenant/sec17/README.md) used these predicates and synthetic users in two branches. Eleven checks passed; branch A's cashier altered branch B's sale total, sale item quantity, sale payment, product price and stock directly. A foreign tenant remained hidden. Real production constraints, triggers and actual HTTP access were not exercised, so classify this as verified permission design plus isolated reproduction, not a live exploit.

The v2 checkout RPC protects its own entry point. It does not protect direct table mutations that never call that function.

## Isolated permission-boundary prototype

The [prototype SQL](../../security-review-null-tenant/sec17/prototype.sql) revokes direct `authenticated` mutations on the five affected tables in a synthetic database. Two `SECURITY DEFINER` operations then demonstrate a trusted path: sale commit calculates its own price from the stored product, requires payment to match, checks active actor, tenant and current branch assignment, decrements stock atomically, and treats exact retries as idempotent; stock adjustment checks an authorized role and branch, uses a delta and recorded reason, rejects negative stock, and records an idempotency event. The [test](../../security-review-null-tenant/sec17/prototype-test.mjs) passed 15 cases, including direct-write denial, changed retries, price changes between retries, revoked branch assignment, cross-tenant attempts and failed-operation rollback. Results are in `prototype-results.json` beside the test.

This is a design proof, **not a deployable migration**. It uses simplified roles, columns, one-product fully-paid sales and no real API/session, returns, promotions, tax, split payments, concurrency or deployed constraints/triggers. It does not implement safe product editing or offline return-parent recovery. The current client still directly writes these tables, so applying the revoke to production now would break supported mobile/desktop workflows. The actual migration must adapt existing v2 checkout and replace every direct writer, then pass real staging and client compatibility checks before broad grants can be removed.

## Existing client dependencies

| Table/action | Checked-in client use | Compatibility consequence |
| --- | --- | --- |
| Sales/items/payments writes | POS `_restoreRemoteSaleSnapshot` upserts sale and deletes/reinserts items/payments during return-parent recovery | Revoking direct writes can prevent an offline sale from being restored before its return |
| Sales reads | POS invoice lookup, sale history/recovery, supplier analytics | Branch-scoped reads may change reports and all-branch owner flows |
| Product writes | Inventory create/update/import/bulk-price, offline sync, customer buy-in | Product policy must distinguish create, price change, normal edit, delete and buy-in workflow |
| Inventory writes | Product creation, thresholds, stock adjustments, buy-in, POS return and offline sync | Stock quantity needs an authorized event/transaction rule; threshold edits are a different permission |
| Client local queue | Offline mutations are replayed later | Revoked rights can cause legitimate queued work to fail; failures must be visible and recoverable |

## SEC-17 source re-scan (2026-10-06)

A current source scan confirms that direct mutation paths still exist beyond the first secure compatibility adapters. Production grant/RLS cutover remains blocked until these paths have secure server equivalents and compatibility tests:

| Area | Direct-write dependency still present |
| --- | --- |
| Customer buy-in | Product/inventory/IMEI/customer-purchase writes and replay queue in `customer_purchase_repository.dart` |
| Inventory | Product, inventory, stock-adjustment and IMEI writes in `inventory_repository.dart` and `inventory_sync_engine.dart` |
| POS returns | Return parent/items, returned-product, inventory and parent-sale recovery writes in `pos_repository.dart` |
| POS buy-in sale linkage | Customer-purchase status and inventory-unit changes while completing a sale in `pos_repository.dart` |

The secure adapters already added for inventory adjustment, product sync and sale-parent restoration retain a legacy fallback only when their RPC is absent. The customer-buy-in and full POS-return atomic routes must be staged before direct permissions can be narrowed.

## Proposed implementation order

1. **Define action and field matrix.** Document which roles/branches may view sales, create a sale, edit product descriptions/prices, adjust stock, and process returns. Clarify owner all-branch access and supported legacy staff behavior. Existing permission catalog includes `inventory.product.*`, `inventory.stock.*` and `pos.sale.create`; determine exact meaning before SQL.
2. **Inventory deployed schema and installed clients.** Use the sanitized export for policies/grants. Inspect actual triggers, constraints, parent links and supported client versions. Map every direct writer, including sync and recovery. Do not infer all native users have updated merely because current source uses a newer RPC.
3. **Protect creation and money changes at a trusted operation boundary.** Keep checkout as the validated sale creation path. Design an authorized, atomic recovery path that verifies original sale identity and immutable financial details before restoring missing parent/children. A generic client-supplied snapshot must not become an alternate way to create or rewrite sales.
4. **Separate inventory operations.** Validate product create/edit, price edit, thresholds, stock adjustment, buy-in and POS return independently. Use server-side actor/branch checks and consistent product/branch relations. Do not accept client-computed stock or prices as authority merely because a client feature gate ran.
5. **Deploy compatible new paths and update clients.** Stage with synthetic data and test Android/Windows/native versions plus planned web version. Test queued offline mutations recorded on an older version. Keep a controlled transition window only if its residual exposure is accepted and time-bounded; broad grants remain a live risk during it.
6. **Close alternate direct writes.** Narrow table grants/policies only after supported clients no longer require unsafe paths. Re-test with direct REST requests as low-privilege users. A second permissive policy can widen access; inspect final effective policies and grants.
7. **Measure and monitor.** Verify no duplicate sales, altered payment totals, negative/phantom stock, or orphaned children under retries/concurrency. Watch authorization rejects and sync queues after staged rollout.

## Release acceptance examples

- Cashier in branch A cannot read or change branch B's sale, payment, product price or stock unless an explicit documented permission allows it.
- Any same-tenant role lacking price-edit permission cannot change `sale_price`, even by direct REST or through a generic product upsert.
- Sale amount/payment/stock invariants hold under direct requests, duplicate retries and offline recovery. Stored state is checked after failed requests.
- Existing owner/cashier actions approved in the matrix still succeed on every supported client version.
- Offline work rejected after revocation is reported clearly and retained for reconciliation; it is not silently marked synced.
- All-branch reports and customer returns still show intended records without exposing other shops.

## Current boundary

This is a transition design, not a tested production patch. The user has required existing mobile/desktop applications to keep working. A safe implementation needs a separate real staging backend and supported client builds; the isolated PostgreSQL fixture cannot provide that validation. SEC-16/03/04 candidates are independent and likewise not deployed. Public repair photos and other findings remain open.
