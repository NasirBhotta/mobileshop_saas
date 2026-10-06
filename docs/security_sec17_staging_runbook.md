# SEC-17 staging runbook

Date: 2026-10-06. This runbook is for a **new, separate Supabase project only**. Never use the production project URL, production database password or production service key in this process.

## Scope and safety boundary

The current production backend remains unchanged. The application has compatibility paths: when a secure RPC does not exist, it uses the current route; when it exists and rejects a request, it does not fall back to insecure direct mutation. This permits a staged rollout without breaking current production clients.

Use synthetic tenant, users, products, IMEIs, accounts, sales and returns in staging. Do not restore production customer, CNIC, photo, payment or transaction data into staging.

## Prerequisites

1. Create a persistent `staging` branch from the actual production Supabase project. It must start from the production schema and configuration, with production data excluded.
2. Do **not** run this repository's 137 incremental migrations against a blank Supabase project: they do not contain the application's original bootstrap schema and can produce an incomplete environment.
3. In the branch, create synthetic owner, manager and cashier users, two branches in one tenant, a separate tenant, active/inactive users, a revoked branch assignment, products, inventory, payment accounts and sample completed sales.
4. Build/run the compatibility-enabled app with **branch-only** values:

   ```powershell
   flutter run -d windows --dart-define=SUPABASE_URL=<staging-url> --dart-define=SUPABASE_ANON_KEY=<staging-publishable-key>
   ```

   Do not commit a staging or production key. Publishable/anon keys are used only in local launch commands; service-role keys never go in Flutter.

## Required preflight

Before applying any draft, run [security_sec17_staging_preflight.sql](security_sec17_staging_preflight.sql) in the **staging branch** SQL Editor. It is one read-only query. Continue only when `safe_to_apply_customer_buyin_draft` is `true`; otherwise retain the output and resolve the missing prerequisite first.

## Additive migration order

Run only these reviewed SQL drafts, one at a time, in the **staging** SQL Editor. Check query success before continuing.

1. `staging_secure_inventory_adjustment_draft.sql`
2. `staging_secure_product_sync_draft.sql`
3. `staging_secure_pos_return_restore_draft.sql`
4. `staging_secure_customer_buyin_draft.sql`

Do not run `prototype.sql`. It is an in-memory synthetic proof, not a migration. Do not revoke table rights, drop policies, change existing grants or run a final cutover script in this phase.

`commit_pos_return_v2` is intentionally not executable SQL yet; its [implementation contract](staging_secure_pos_return_restock_draft.md) requires a staging integration implementation because it joins return approval, restock and cash/credit ledger posting. Do not bypass this by applying a generic direct-write policy change.

## Required evidence after each migration

Run the relevant test plan and retain the result:

| Migration | Evidence |
| --- | --- |
| Stock adjustment | [test plan](staging_secure_inventory_adjustment_test_plan.md) |
| Product sync | [test plan](staging_secure_product_sync_test_plan.md) |
| Sale parent restore | [test plan](staging_secure_pos_return_restore_test_plan.md) |
| Customer buy-in | [test plan](staging_secure_customer_buyin_test_plan.md) |

For every RPC test, perform both a positive action through the app and a negative direct REST/table request using a low-privilege synthetic user. Confirm the rejected request leaves no records, stock, balances or ledger entries changed.

## Staging acceptance gate

The staging project is ready for the next implementation only when:

- Existing client flows still work before and after an additive RPC is installed.
- Secure route is used by the compatibility-enabled client when the RPC exists.
- Cross-tenant, other-branch, inactive/deleted and revoked-assignment calls are rejected.
- Exact retry is idempotent; changed retry is rejected.
- Offline queue preserves its original IDs and surfaces terminal authorization errors.
- Product/stock/financial values remain correct after failure, retry and concurrent requests.
- Flutter checks remain green:

  ```powershell
  flutter analyze
  flutter test test/features/inventory/inventory_sync_engine_test.dart
  flutter test test/features/pos/data/repositories/sale_return_parent_recovery_test.dart test/features/pos/pos_return_refund_ledger_test.dart
  ```

## What remains after staging setup

1. Implement and validate the full `commit_pos_return_v2` server transaction in staging.
2. Move buy-in client and its offline queue to `commit_customer_buyin_v2` with its fallback pattern.
3. Test all secure RPC paths on staging clients.
4. Prepare the final production cutover migration that narrows direct grants/RLS only after the client rollout is complete.

## Stop conditions

Stop the staging rollout if an existing app action fails, a queue becomes stuck, a retry changes data twice, a ledger/account mismatch appears, or a direct mutation remains allowed after its final cutover test. Preserve the synthetic evidence and fix the specific operation; do not copy staging SQL to production or re-open broad access as a rollback.
