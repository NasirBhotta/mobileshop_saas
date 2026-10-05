# Read-only security audit — POS, inventory, repairs, admin, offline

**Later evidence:** The supplied Supabase snapshot blocks the legacy checkout route and does not contain the two legacy inventory RPCs. See [snapshot verification and corrected priorities](security_export_verification.md) before acting on source-only findings below.

Date: 2026-10-05 (Asia/Karachi)

## Scope and conclusion

This extends [the initial audit](security_read_only_audit.md). Existing source, SQL migrations, tests, configuration, and deployed applications were left unchanged. No SQL was executed, no live application API was called, and no mutating/load tests were run. This turn adds documentation only.

The most urgent new source finding is an October migration that reopens authenticated execution of the older checkout function after an August security migration deliberately revoked it. That gives a direct route around the newer checkout wrapper's checks if deployed as written.

Other findings concern bulk-price editing, branch/action isolation on repair and return tables, sensitive customer buy-in data, and local cache retention. No live exploit was reproduced. Source findings below assume ordinary migration execution with privileged function ownership; deployed owners, effective grants, policies, and extra controls are still unknown.

## Priority summary

| ID | Provisional priority | Finding | Status |
| --- | --- | --- | --- |
| SEC-09 | High — first verification priority | Legacy checkout execution regranted, bypassing hardened wrapper | Confirmed migration-level regression; live deployment unknown |
| SEC-10 | High | Bulk-price RPC lacks current account/action authorization | Confirmed source gap; runtime ownership/grants unknown |
| SEC-11 | High | Inventory-unit and repair-ticket direct policies do not enforce staff branch/action scope | Confirmed predicates; live effective permissions unknown |
| SEC-12 | High | Return tables remain writable/readable with broader checks than refund RPCs | Confirmed source policy gap; arbitrary financial impact not reproduced |
| SEC-13 | High | Customer buy-in records expose sensitive fields tenant-wide and accept unrelated object IDs at schema level | Confirmed policy/constraint gap; live constraints unknown |
| SEC-14 | Medium | Ordinary logout does not visibly clear persistent business/permission caches | Confirmed reviewed code behavior; cross-account UI leak not established |
| SEC-15 | Medium | Repair-payment retry path evaluates stored payment before authorization | Confirmed response-oracle path; no unauthorized payment creation established |
| VERIFY-01 | Verification required | Privileged admin MFA/step-up assurance not established | Membership guards found; no source proof of AAL2 enforcement |

## SEC-09 — Hardened checkout can be bypassed through a reopened legacy RPC

**Evidence and chronology**

1. `supabase/migrations/20260809000300_secure_pos_checkout_and_discount_approval.sql:174` explicitly revokes authenticated execution of `commit_pos_sale(jsonb)`.
2. The same file, lines 247–263, exposes `commit_pos_sale_v2`, validates item/totals through `validate_pos_sale_amounts`, then calls the protected renamed implementation. Direct execution of the unvalidated implementation is revoked.
3. `20260728000500_pos_payment_account_linkage.sql:79` shows the underlying v2 implementation checking `pos.sale.create` through `current_user_has_branch_permission`, then validating account/payment linkage and posting ledger entries.
4. Later, `20261003000100_preserve_sale_item_imei.sql:198` revokes PUBLIC/anon only and line 199 grants the legacy `commit_pos_sale(jsonb)` back to authenticated and service-role callers.
5. That legacy body checks caller ID and that a branch belongs to the same tenant (lines 29–38). It does not call the action-aware branch permission helper, the amount-validation wrapper, or the v2 payment-account/ledger flow. It uses submitted monetary values and compares payment sum with submitted total, rather than establishing the wrapper's full amount invariants.
6. `lib/features/pos/data/repositories/pos_repository.dart:93` uses v2. The UI choosing v2 does not prevent an attacker invoking the newly granted legacy route.

**Attack scenario:** A same-tenant user calls the legacy RPC directly, including a branch or action they cannot use through v2. A matching payment/total payload can also avoid the newer calculations/account-linkage entry point. Stock and ordinary database constraints still apply; this is not a claim that every arbitrary payload succeeds.

**Impact:** Backend role/branch enforcement and financial invariants are inconsistent between two exposed checkout paths. The legacy body also does not explicitly reject disabled/deleted users inside its privileged lookup. Deployed function ownership and other database controls determine effective impact.

**Proposed fix — not applied:** First inventory old native/web clients that may still call the legacy endpoint. Either make it an internal-only primitive again, or enforce equivalent authorization and financial invariants at every exposed entry point. Preserve legitimate v2 internal calls and new IMEI snapshot behavior. Merely changing Flutter's route is insufficient.

**Safe proof later:** In a disposable database, test v1 and v2 with the same restricted actor and synthetic sale. Both must reject a forbidden branch/action and inconsistent totals. Authorized checkout must preserve stock, sale items, IMEI fields, payment linkage, and ledger consistency; retries must not duplicate effects. Add a regression test for the final effective function grants after ALL migrations.

**Interview explanation:** “An earlier security patch closed an alternate endpoint, but a later feature migration reopened its grant. I traced migration order and both entry points; security must be checked against the final deployed permissions, not only the intended UI flow.”

## SEC-10 — Bulk-price RPC has scope filtering but no action authorization

**Evidence:** Latest definition is `20260703001000_fix_bulk_price_rpc_signature.sql:3`, not the preceding migration's original body. `bulk_update_product_prices(text[], numeric, text)` is SECURITY DEFINER and grants authenticated execution. It authenticates a user, resolves tenant/selected branch, optionally chooses the first tenant branch, and updates selected product prices. It does not check a price-edit permission, active/deleted account status, or current branch-role assignments.

**Threat:** A logged-in user without pricing authority may call the RPC directly for products in the derived branch. Tenant filtering prevents this particular query from freely updating another shop, but does not establish the action is permitted. A stale selected branch also inherits the initial audit's revocation concern.

**Proposed fix:** Require active account, current branch authorization, and the appropriate inventory price-edit permission before the update. Do not silently choose a branch as a substitute for authorization. Preserve authorized bulk editing and its price-history trigger.

**Verification:** Restrict a synthetic cashier's price permission; call RPC directly and confirm no product/history mutation. Positive tests cover an authorized editor and valid legacy clients. Repeat with disabled staff and revoked branch assignments.

## SEC-11 — Repair and inventory-unit table access is broader than the action-aware RPCs

**Evidence:** `20260707000100_repair_module_foundation.sql:342` gives authenticated callers FOR ALL access to `inventory_units` when its branch belongs to the caller's tenant. Lines 370–428 define repair-ticket SELECT/INSERT/UPDATE policies with the same tenant/branch-belongs-to-tenant logic; these do not check the user's assigned branch or an action permission. No subsequent explicit replacements of these policies were found in the migration search.

The newer repair completion/cancellation/parts functions in `20260728001500_repair_hybrid_financial_engine.sql` perform explicit `current_user_has_branch_permission` checks. The existence of those safer functions does not narrow the older direct-table policies.

**Threat:** A staff member can potentially query another branch's repair tickets or invoke permitted direct mutations without the permission enforced by the dedicated workflow. Whether specific financial/status edits succeed depends on actual grants, column restrictions, constraints, and triggers; that was not executed.

**Proposed fix:** Separate read/update/action permissions at the table/API boundary. Restrict sensitive lifecycle/financial fields to validated operations while retaining intended editable repair fields. Review inventory units' parent product/customer/sale references and existing client writes before modifying grants.

**Verification:** Direct reads/updates from branch-restricted and read-only staff must fail outside scope; permitted technicians must retain intended edits. Compare raw table access with completion/cancellation RPCs and inspect stored state after rejection.

## SEC-12 — Return-table policies remain broader than protected refund operations

**Evidence:** `20260706000000_pos_returns.sql:159` onwards allows sale-return reads/inserts across a user's tenant branches. The update policy relies on the legacy `users.role` being manager/owner, rather than current action permissions. Item SELECT/INSERT/DELETE policies traverse the return's branch to the tenant, but do not require the current staff branch/action entitlement. No later explicit replacements were found.

By contrast, `20260728000600_pos_return_refund_ledger.sql:78` checks `pos.sale.return` before posting a monetary refund, and validates refund allocations/account scope. `post_pos_credit_return` likewise has an action-aware check.

**Threat:** Direct requests can potentially disclose another branch's returns or alter records that the newer workflow would reject. The audit does not establish an unrestricted cash-refund exploit; the ledger functions have additional protections. Direct edits can still undermine assumptions about approved return data.

**Proposed fix:** Define permitted direct edits by return state and role, enforce current branch/action permissions, and protect immutable approved financial fields. Preserve valid partial returns, cash/credit refunds, and compatibility with existing clients.

**Verification:** Exercise direct return/item requests as unauthorized staff, compare legacy-manager role against revoked current permissions, and confirm ledger/state consistency for authorized workflows. Use synthetic data only.

## SEC-13 — Sensitive buy-in records need narrower access and relationship validation

**Evidence:** `20260823000100_customer_buyin_second_hand_purchases.sql` stores seller CNIC, phone, address, photo/document URLs, IMEIs, prices, and account references. Lines 45–55 authorize SELECT/INSERT/UPDATE solely by tenant membership. Branch/product/category/account foreign keys independently check referenced IDs, rather than tenant/branch consistency. No added customer-purchase constraint/validation migration was found in the source search.

**Threat:** Staff can potentially access CNIC details across branches without a dedicated permission. An insert/update may use the caller's legitimate tenant ID while referencing another tenant's existing branch/product/account ID. This describes inconsistent cross-tenant linkage, not proof that a referenced foreign row itself can be read or charged.

**Proposed fix:** Apply role/action and branch restrictions, minimize sensitive field access, and validate composite tenant/branch relationships. Ensure account debits, inventory changes, and purchase records are validated together through an appropriate atomic workflow. Review document storage separately; a URL field does not prove a bucket is public.

**Verification:** Known foreign fixture IDs must fail validation. Staff without buy-in authority must not retrieve CNIC/document fields. Existing legitimate purchase and inventory/accounting flows must pass compatibility tests.

## SEC-14 — Logout/cache behavior needs an explicit retention policy

**Evidence:** `lib/features/auth/presentation/providers/auth_provider.dart` ordinary logout signs out and invalidates providers; the auth-state listener also invalidates in-memory providers. No persistent data purge is visible in those paths.

`lib/config/router/app_router.dart:250` calls `OfflineStore.clearUserSessionCache` after a revoked identity is detected. That method in `lib/core/offline/offline_store.dart:171` clears profile, selected branch, branch-access and setup mutation entries, not all business tables or persistent permission entries.

`lib/core/authorization/persistent_permission_cache.dart` keys permissions by tenant/user, records `cached_at`, but its loader does not enforce cache age. Reviewed data sources can fall back to this cache. `lib/core/local/local_database.dart` uses a persistent native SQLite file; it is not proof of implemented iPhone-browser storage behavior.

**Threat/limit:** A person with local app/browser-storage access may recover retained business data or manipulate local cached authority. No cross-account UI disclosure was established; cache keys and provider resets provide some separation. Client cache manipulation is not a remote backend bypass when backend authorization is correct.

**Proposed fix:** Specify cache lifetime, logout behavior, shared-device policy, and offline access boundaries. Revalidate permissions on synchronization and use backend checks regardless of cache state. Do not blindly delete queued unsynced business work; distinguish pending transactions from reusable sensitive cached data and design safe sign-out behavior.

**Verification:** In an isolated app profile, test account switching, logout, offline restart, revoked access, stale permissions, and pending unsynced work. Never clear the user's working database for this audit.

## SEC-15 — Retry shortcut occurs before repair-payment authorization

**Evidence:** `20260728001000_repair_payment_account_ledger.sql:65` locks on the requested payment ID and reads an existing payment. It can return a conflict error or `false` for an exact retry before loading the ticket and checking `repair.payment.create` at line 91.

**Threat:** Given another tenant's valid payment ID, a caller may distinguish existing payment/retry states through responses. The early return does not create a new payment; the normal new-payment path performs permission and account-scope checks.

**Proposed fix:** Authorize the actor against the stored payment/ticket before returning a retry result or disclosing conflict details. Keep idempotent behavior for authorized retries.

**Verification:** Cross-tenant known payment IDs must not provide a distinct authorized retry/conflict response. Legitimate identical retries still return the documented result without duplicate ledger entries.

## Admin review — protections and remaining assurance questions

A name-based scan of latest top-level migration definitions found 58 distinct `platform_*` function names (overloads collapsed). Forty-seven bodies referenced the active-admin guard or membership check. The remaining eleven are low-level entitlement functions explicitly restricted to service-role execution by the grants loop in `20260715000800_secure_entitlement_management_rpcs.sql`. This is an inventory check, not proof every endpoint is correct.

Reviewed public facades call `require_active_platform_admin()` defined in `20260715001000_platform_admin_tenant_management.sql:3`; it rejects missing/inactive platform membership. Shop ownership is not treated as platform administration. No direct shop-user-to-platform-admin bypass was established in this pass.

The reviewed guard does not check MFA assurance/AAL2. Provider-level MFA policy and the full session lifecycle are unknown. Record VERIFY-01 until deployed assurance enforcement is inspected; do not infer that MFA is definitely disabled from the absence of an inline check.

## Live verification readiness — blocked by unavailable access, not by permission

The user authorized read-only verification. No extra approval is being invented. Available tools were inspected; no relevant Supabase/database connector for this application was exposed. The unrelated Sites database tools are not this project's database connection.

Presence-only checks found no `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `DATABASE_URL`, `SUPABASE_DB_URL`, or standard PostgreSQL connection/password variables in this process. `supabase`, `psql`, and Docker were not on PATH; Python PostgreSQL drivers were absent. Conventional workspace environment files and `supabase/config.toml` were absent. `.temp` contains linked-project metadata, which identifies a project but does not establish authenticated access. Secret values were not printed, and credential stores were not searched.

**Needed next:** A securely configured read-only database/management connection, or a sanitized catalog export covering owners, RLS policies, effective table/column/function privileges, relevant definitions, bucket flags, and migration versions. Do not paste service keys/passwords into chat. Query templates are supplied in [Live Security Verification](security_live_verification.md); they were not executed.

## Execution status

- Completed: focused source review of requested modules, latest-definition/grant tracing, connection-readiness check, and documented proposed fixes/verification.
- Not completed: live classification, complete permission matrix for every endpoint, runtime attack tests, performance tests, independent review, or remediation.
- Existing code and deployed behavior remain unchanged. Git tracked/staged diff checks are used to confirm no tracked code changes in this turn.

## Next priority order

1. Verify the deployed legacy checkout grant/body and repair-photo public flag.
2. Verify disabled-account/branch revocation and direct table/action gaps from both audit reports.
3. Reproduce with synthetic fixtures in isolation only when authorized; plan backward-compatible fixes for all existing clients.
4. Apply no fixes without the user's explicit approval under the current restriction.
