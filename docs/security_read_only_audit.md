# Read-only security audit — initial source review

**Later evidence:** [Supabase snapshot verification](security_export_verification.md) now classifies these findings using the user-supplied metadata and records important corrections and additional gaps.

Date: 2026-10-05 (Asia/Karachi)

## Outcome and scope

The reviewed source contains authorization gaps that prevent a production-security sign-off. The strongest immediate link-access concern is the public repair-photo bucket. Additional concerns affect branch isolation, disabled-account access, and a cross-tenant inventory helper.

This was a local, read-only source audit. Application code, migrations, tests, deployment configuration, and live services were not changed. No database connection, live API request, test execution, load test, or migration application was performed. Only this documentation file was created during this audit turn.

“Source-confirmed” below means the relevant behavior or missing check is visible in checked-in code. It does NOT mean exploitation has been reproduced against the running service. Live owners, grants, schema exposure, additional policies, deployed versions, token configuration, and provider controls remain unverified. Severity is provisional and assumes these surfaces are deployed and accessible as intended by the repository.

This is a prioritized first-pass audit, not an exhaustive review of every function or a penetration test. The inventory is a discovery aid, not proof of full coverage.

## Findings summary

| ID | Priority | Finding | Evidence status |
| --- | --- | --- | --- |
| SEC-01 | High | Repair photos are configured for unauthenticated public retrieval | Source-confirmed configuration and client behavior; live bucket unknown |
| SEC-02 | High | Procurement policies allow tenant-wide operations without branch/action checks | Source-confirmed policy predicates; deployed effective access unknown |
| SEC-03 | High | Tenant/permission helpers omit disabled/deleted-account checks | Source-confirmed helper chain; owner/RLS/runtime effects unverified |
| SEC-04 | High | Branch-access helper trusts selected branch after assignment revocation | Source-confirmed predicate and revocation path; live behavior untested |
| SEC-05 | Medium | Inventory-status RPC accepts arbitrary product IDs without ownership checks | Source-confirmed function and authenticated grant; live exposure unknown |
| SEC-06 | Medium | Repair-photo policies permit an alternate token-metadata path without current account checks | Source-confirmed OR predicate; requires populated tenant metadata |
| SEC-07 | Review required | PIN verification has no visible attempt budget in its function | Source-confirmed absence locally; provider/gateway controls unknown |
| SEC-08 | Low | Invitation errors expose internal error text and execution stage | Source-confirmed response construction; disclosure depends on error |
| OPS-01 | Release concern | Migration versions collide and complete foundational schema is not present in reviewed migrations | Source-confirmed file layout; migration replay not attempted |

## SEC-01 — Public repair photos defeat private link authorization

**Evidence:** `supabase/migrations/20260822000100_repair_ticket_photos.sql:9` inserts `repair-photos` with `public = true` and sets it true on conflict. `lib/features/repairs/data/repositories/repair_repository.dart:225` builds the tenant/ticket object path; line 234 calls `getPublicUrl`.

**Threat:** Someone who obtains a repair-photo URL can retrieve the image without proving shop membership. This does not require guessing a UUID or changing an invoice route. A link copied from a legitimate session is sufficient if the bucket is deployed as public.

**Why:** The accompanying SELECT policy does not make public object retrieval private. Supabase explicitly documents that public buckets bypass access controls for retrieval/serving, while other operations retain access controls. [Supabase bucket access model](https://supabase.com/docs/guides/storage/buckets/fundamentals)

**Proposed solution, not applied:** Store object paths and load photos through authenticated private access or short-lived, authorized signed URLs. Coordinate client compatibility first, then make the bucket private. Review previously distributed URLs and caching. Changing the bucket alone could break existing repair screens, so it must not be done as an isolated production fix.

**Safe verification later:** In a disposable environment, upload a synthetic image. Verify an unauthenticated known URL and another tenant's request fail after the change, while the owning authorized account can display it in existing applications. Test old stored public URLs through a compatibility migration path.

**Interview explanation:** “The application had tenant policies around storage, but its public delivery mode bypassed those read checks. The proposed fix changes how files are served, rather than relying on the secrecy of the URL.”

## SEC-02 — Tenant isolation is not branch or action authorization

**Evidence:** `supabase/migrations/20260708000100_supplier_procurement_module.sql:667` through line 701 defines FOR ALL policies for `supplier_products`, `purchase_orders`, `purchase_order_items`, `goods_receipts`, `goods_receipt_items`, and `supplier_payments`, using only `tenant_id = current_user_tenant_id()` for access and writes. Repository-wide searches found no later explicit replacement of these named policies. `20260729000900_supplier_branch_isolation.sql:13` strengthens `suppliers` only.

`20260714000100_revoke_non_runtime_table_privileges.sql` explicitly preserves authenticated CRUD grants on its listed baseline tables. Some later operations have extra triggers/validation, so do not infer that every arbitrary write succeeds.

**Threat:** Staff belonging to the correct tenant can potentially read another branch's purchase orders/payments or directly perform operations that the UI restricts. Removing a client branch filter does not encounter a branch check in these policies. Even the strengthened supplier policy checks branch access, not a per-action permission.

**Impact:** Same-shop branch confidentiality and role separation are weaker than the planned access model. This finding is not a demonstrated cross-shop bypass of these tables.

**Proposed solution:** Define which roles may perform tenant-wide procurement operations, then add corresponding action/branch checks. Prefer narrowly authorized financial mutations where needed. Review ALL operations and effective grants together; adding a second permissive policy does not tighten an existing broad policy. PostgreSQL combines permissive policies with OR. [PostgreSQL row security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)

**Safe verification later:** With two branches in one tenant and restricted staff, request another branch's rows without frontend filters. Test read/count/export first, then mutations only in a disposable database. Verify permitted owner-wide workflows continue to work.

## SEC-03 — Disabled-account protection does not cover older privileged helpers

**Evidence:** Latest checked-in definition of `current_user_tenant_id()` is `20260709000100_expense_management_module.sql:13`. It is SECURITY DEFINER and reads `users` by `auth.uid()` without testing `is_active` or `deleted_at`.

`current_user_has_permission()` in `20260715000400_secure_role_management_rpcs.sql:24` checks role/assignment status but not the user's active/deleted state. `require_role_manager_tenant()` at line 68 uses that permission helper and a similarly unrestricted user lookup. `20260719000700_create_role_with_permissions.sql:15`, staff invitation creation, and `20260731000100_role_managers_list_tenant_users.sql:15` depend on this helper chain.

`20260719000600_enforce_active_user_restrictive_rls.sql` adds a restrictive policy on `public.users`; it is not a global actor check across all business tables. A definer executing with table-owner/BYPASSRLS authority may bypass that users policy. Function ownership/FORCE RLS have not been inspected live.

**Threat:** A disabled user retaining an unexpired token and role assignments may still resolve a tenant or a role-management permission through privileged functions. That can permit calls which the normal profile UI rejects.

**Proposed solution:** Enforce active/non-deleted actor state inside shared privileged authorization helpers and audit their callers. Review tenant suspension/entitlement requirements separately. Decide session revocation semantics explicitly rather than assuming frontend sign-out closes every path.

**Safe verification later:** Disable a synthetic role manager while retaining the old test token and assignments. Check procurement reads, role-directory access, and role-management RPCs. They should reject; an active manager should still succeed. Inspect function owners and effective grants as part of the test setup.

## SEC-04 — Revoking a branch assignment may leave selected-branch access

**Evidence:** `current_user_can_access_branch()` in `20260725000100_mobile_services_foundation.sql:40` allows an active same-tenant user when they are owner OR `users.branch_id = p_branch_id`. It does not inspect branch-role assignment revocation.

`set_user_branch_role()` in `20260726000200_branch_scoped_role_foundation.sql:135` revokes assignments without clearing the user's selected branch. `cleanup_revoked_branch_role_overrides()` in `20260726000300_secure_branch_permission_overrides.sql:31` clears overrides only. `20260726000500_enforce_branch_selection_access.sql` checks updates to branch selection; it does not reauthorize reads using an already selected branch. `20260729000900_supplier_branch_isolation.sql` relies on the older branch-access helper.

**Threat:** A staff member selects branch A, then loses its assignment, but continues accessing a surface that trusts the selected branch. The newer action-aware helper in `20260728000050_branch_permission_sql_evaluator.sql` contains better historical/revoked-assignment handling, but that does not automatically replace older helper callers.

**Proposed solution:** Derive allowed branch access from current assignments, with an explicitly documented legacy-user policy. Do not use the currently selected branch as proof of authorization. Audit callers before changing a shared helper to avoid breaking valid owner and legacy flows.

**Safe verification later:** Revoke the active assignment without switching the client's branch; attempt supplier reads and other older-helper paths. Compare with an assigned user, an owner, and any intentionally supported legacy configuration.

## SEC-05 — Cross-tenant inventory-status oracle

**Evidence:** `supabase/migrations/20260703000000_inventory_edit_bulk_history_imei.sql:183` defines SECURITY DEFINER `product_has_active_imei_units(p_product_id uuid)`. Its query filters only by product ID and unsold/non-empty IMEI state; line 217 grants execution to authenticated. No later replacement or specific revocation was found.

**Threat:** A logged-in user with another tenant's product ID may learn whether that product has unsold IMEI inventory. This is a boolean information leak, not disclosure of actual IMEI values or full product records. Anonymous execution is unverified because effective default/function grants were not inspected.

**Proposed solution:** Validate caller activity, product ownership, and required scope before querying; restrict execution grants explicitly. Maintain the behavior needed by existing inventory editing flows.

**Safe verification later:** Seed products with and without units in two shops. A caller must not distinguish the other shop's inventory state using this RPC; authorized own-shop calls should retain correct results.

## SEC-06 — Photo policies allow stale tenant claims as an alternative

**Evidence:** `20260822000100_repair_ticket_photos.sql:22` onwards includes an OR branch comparing the first object-path segment with `auth.jwt()->'app_metadata'->>'tenant_id'`. That branch is independent of the active/non-deleted user lookup and is repeated in INSERT/UPDATE/DELETE policies.

**Threat:** If tenant metadata is populated, an otherwise valid token can satisfy the alternative branch after the corresponding database account is disabled or its membership changes. This is not an assertion that ordinary users can forge signed app metadata. It is a stale-authority issue. Policies also lack ticket/branch/action checks within a tenant.

**Proposed solution:** Make current server-side membership/account state mandatory and validate the repair/ticket scope. Treat token metadata as a hint rather than an alternate path around revocation checks.

**Safe verification later:** Use a token with tenant metadata, then disable the synthetic account or change membership. Test object mutation in a private test bucket. Verify behavior with and without metadata, and across restricted branches.

## SEC-07 — Approval PIN attempts need an endpoint-level limit review

**Evidence:** `20260809000300_secure_pos_checkout_and_discount_approval.sql:42` defines `verify_pos_discount_approval`; lines 167–170 grant authenticated execution. The function checks an active actor and bcrypt PINs but contains no visible durable attempt counter, cooldown, or lockout budget.

**Risk:** A logged-in same-tenant attacker could repeatedly call the verification function to guess a short approval PIN or consume bcrypt CPU. Existing external rate limiting has not been inspected, so this is a verification item rather than a claim that no protection exists anywhere.

**Proposed solution:** Bound attempts using a durable per-actor/tenant budget and safe recovery behavior; protect direct RPC access as well as any gateway. Review whether approvals must be bound to a particular sale/action.

**Safe verification later:** In staging, a small controlled number of attempts should trigger the declared limit; a valid authorized approval and recovery flow should work. Do not brute-force real PINs.

## SEC-08 — Invitation response includes internal errors

**Evidence:** `supabase/functions/invite-staff/index.ts:108` returns `{ error: message, stage }`; the error helper can pass through database/provider messages and details.

**Risk:** Error conditions may disclose internal schema/provider information. This does not by itself establish unauthorized mutation. Wildcard CORS is not being reported as an authentication bypass.

**Proposed solution:** Map errors to safe client codes/messages and log sanitized diagnostic details behind a correlation ID. Preserve user-actionable messages where safe. Separately review privileged cleanup/retry ownership; no destructive-cleanup exploit was established in this pass.

## OPS-01 — Schema and deployment reproducibility gaps

Observed duplicate top-level migration versions:

- `20260708000300`: repair status policy and reporting analytics.
- `20260802000100`: branch default cash account and repair effective date.
- `20260802000200`: repair part return ledger and dashboard preferences.

A nested migration also exists under `supabase/migrations/supabase/migrations/`. Core tables such as users/products/sales are referenced but their foundational CREATE TABLE definitions were not found in the SQL scan. This limits reconstruction of the full security baseline from these files alone.

**Proposed next step:** Compare the applied migration ledger and sanitized schema/grants export with the repository, then rehearse only in an isolated environment. Do not rename applied migrations or reorder production history without an explicit reconciliation strategy. No replay was attempted here, so actual tooling failure is not claimed.

## Existing protections observed (not runtime-certified)

- User profile updates have a field-protection trigger; direct changes to authority fields are not simply accepted by the reviewed trigger (`20260714000600_protect_users_sensitive_fields.sql`, with later lifecycle/selection changes).
- Role-management SQL checks tenant ownership and restricts management through server functions.
- Entitlement administration functions that lack inline caller checks are explicitly restricted to `service_role` by the grants loop in `20260715000800_secure_entitlement_management_rpcs.sql`; absence of an inline check alone was not reported as a public exploit.
- Account branch protections, composite tenant/branch relationships, POS idempotency, and approval-PIN hashing exist in migrations.
- `current_user_has_branch_permission()` explicitly handles active accounts and historical branch assignments to avoid a revoked assignment restoring its legacy fallback.
- Security regression SQL files exist. They were not run, and static migration-text tests are not substitutes for exercising database permissions.

## Surface inventory and coverage

Discovery scanned 137 top-level SQL migrations and Flutter sources in `lib/` and `admin_portal_export/lib/`. A lightweight function-name scan found 177 distinct latest names, collapsing overloads; this is not a verified signature count. Dynamic SQL, grants loops, triggers, comments, and pre-existing schema make regex-only completeness claims unreliable.

Literal client calls identify 58 table-like `.from(...)` targets plus the `repair-photos` storage bucket, and 76 RPC names. Dynamic client abstractions and unused exposed backend functions can add more surfaces.

| Surface | Reviewed in this pass | Remaining verification |
| --- | --- | --- |
| Tenant/account identity | Current tenant, account activity and role helpers | Live owners, grants, suspension and revocation behavior |
| Roles and branch permissions | Management helpers, branch selection/revocation, newer evaluator | Full action matrix and all management RPCs |
| Procurement | Direct policies, supplier policy, client direct access | Effective grants, write triggers, parent/child consistency |
| Repair photos | Bucket config, policies, URL generation | Actual bucket state, cached links, ticket/branch permissions |
| Inventory | IMEI-status helper | Full product/inventory policies and mutation paths |
| POS | PIN function, wrapper/grant structure | Concurrency, all direct-write alternatives, sale/return/refund authorization |
| Invitations | Caller validation, privilege split, response handling | Partial failures, replay, cleanup and session behavior |
| Platform admin | Selected grant restrictions | All admin endpoints and MFA enforcement |
| Local/offline/auth UI | Located cache and sign-out mechanisms | Full cache-isolation and offline revocation behavior |
| Hosting and operations | No deployed inspection | TLS/CSP, rate limits, secrets handling, backups, alerts, spending |

### Literal client table targets

`account_transactions`, `accounts`, `branches`, `business_report_delivery_jobs`, `business_report_schedules`, `categories`, `customer_ledger_entries`, `customer_purchases`, `customer_settlements`, `customers`, `discount_audit_logs`, `expense_categories`, `expenses`, `held_carts`, `inventory`, `inventory_units`, `mobile_service_charge_rules`, `mobile_service_providers`, `mobile_service_transactions`, `permissions`, `plan_features`, `plan_limits`, `product_price_history`, `products`, `purchase_order_items`, `purchase_orders`, `recurring_expense_rules`, `repair_financial_events`, `repair_part_returns`, `repair_parts`, `repair_payments`, `repair_status_logs`, `repair_tickets`, `role_permissions`, `roles`, `sale_items`, `sale_payments`, `sale_return_items`, `sale_returns`, `sales`, `sales_report_delivery_jobs`, `sales_report_schedules`, `stock_adjustments`, `supplier_ledger_entries`, `supplier_payments`, `supplier_products`, `suppliers`, `tenant_feature_overrides`, `tenant_limit_overrides`, `tenant_settings`, `tenant_subscriptions`, `tenants`, `user_branch_dashboard_preferences`, `user_branch_permission_overrides`, `user_branch_role_assignments`, `user_role_assignments`, `users`, `void_logs`.

## Next steps within the user's constraints

1. Keep existing code and deployed behavior unchanged. This report contains proposals only.
2. Continue source review for the unverified modules using this inventory; attach exact access-matrix entries and findings rather than declaring blanket safety.
3. Obtain read-only deployed schema/grants/policy/function-owner/bucket/migration evidence through an available authorized connection or sanitized export. This pass neither located credentials nor connected to production.
4. Reproduce priority findings in an isolated environment with synthetic fixtures once that work is explicitly authorized. Do not run the repository's data-mutating SQL tests against production.
5. Prepare fixes only after explicit approval under the user's restriction. Coordinate database and existing native/web client compatibility, particularly for photo URLs and shared authorization helpers.

**No remediation has been applied. No live exploit or absence of live vulnerability has been demonstrated.** The priority is to close the identified source-level gaps through reviewed, compatible changes and verified evidence before a production-security claim.
