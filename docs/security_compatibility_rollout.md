# Security fixes: compatibility and rollout plan

Date: 2026-10-05. Status: source-backed proposal only; no fixes, migrations, test runs, or deployments performed.

User constraint: preserve existing applications and do not modify implementation without explicit approval. This document prepares that decision; it does not authorize deployment or promise zero regressions.

## Newly traced compatibility facts

| Area | Current client behavior | Consequence for a future fix |
| --- | --- | --- |
| Checkout | `lib/features/pos/data/repositories/pos_repository.dart:93` calls `commit_pos_sale_v2`; its offline sale sync also uses `_commitSaleRemote` | Current checked-in client uses v2, but older installed binaries remain unknown |
| Checkout internals | v2 delegates to its renamed implementation, which calls legacy `commit_pos_sale` internally | Do not remove the internal primitive or forward it back to v2: that can create recursion |
| Photo upload | `repair_repository.dart:234` returns a public URL and accepts already-HTTP paths unchanged | Making the bucket private alone will break these URLs in existing clients |
| Photo rendering | Repair list/form screens use `Image.network(path)` for remote photos | Introduce an authorized media resolver before private-bucket cutover |
| Photo offline sync | `repair_repository.dart:1397` distinguishes HTTP URLs from local file paths | Bare object paths need explicit representation; otherwise they can be mistaken for local files |
| Inventory pricing | `inventory_repository.dart:1876` reaches direct per-product updates, not the legacy bulk-price RPC | Hardening/removing the RPC alone does not secure the currently used price-write path |
| Returns | `pos_repository.dart:2072` upserts return, then deletes/reinserts items | Blanket write-grant revocation would break existing return synchronization |
| Repairs | Repository writes/upserts `repair_tickets` directly in creation, update and sync paths | Protect sensitive fields without accidentally blocking normal repair synchronization |

These are source observations, not a deployed-client inventory. Current native and future web clients share backend effects; an iPhone-only frontend does not isolate database changes from Windows/Android clients.

## 1. First candidate: close the reopened legacy checkout route

Related finding: SEC-09, [Phase 2 audit](security_read_only_audit_phase2.md).

### Proposed design

Keep v2 as the public validated checkout entry point and retain the underlying legacy commit only for its authorized internal call chain. Revoke direct execution from untrusted caller roles only after verifying the deployed ownership/grants and all supported client versions. Preserve the IMEI/unit snapshot additions from October.

Do not implement `commit_pos_sale -> commit_pos_sale_v2` forwarding: the existing v2 implementation calls `commit_pos_sale`, so this would recurse. If legacy clients must remain supported, design a separate guarded public compatibility entry and internal primitive with a non-recursive call graph, preserving required payload/accounting semantics. An old payload missing required security/accounting information may require a client update; no silent inference or weakened validation should be used merely for compatibility.

### Required evidence before change

- Actual live signatures, grants, function owners and final definitions.
- Supported release versions and whether any still call v1 directly; repository search alone cannot prove installed-client behavior.
- Baseline authorized sale, credit sale, cash/card/wallet payments, IMEI receipt, ledger and stock outcomes.
- Representative queued offline payload formats, collected without exposing real customer data.

### Regression criteria

| Case | Required outcome |
| --- | --- |
| Direct legacy call by regular authenticated user | Denied if legacy route is internal-only |
| Current-client valid v2 sale | Completes once with correct inventory, items and ledger |
| Staff missing sale action / wrong branch / disabled account | Denied before any financial mutation |
| Modified item amounts or inconsistent totals | Rejected; no partial sale |
| Same authorized request repeated after lost response | No duplicate effect; client receives an understood retry result |
| Concurrent sale of limited stock | No oversell or ledger inconsistency |
| Old queued sale with supported format | Safe sync or explicit actionable failure without losing queue data |
| Receipt/reprint after sync | IMEI, device details and unit identity preserved |

One integration detail needs testing: the reviewed client throws when `_commitSaleRemote` receives `false`, while the underlying database commit can return `false` for an existing sale. Do not change that contract during a grant-only fix without separately checking retry and ledger behavior.

### Existing test limitation

`test/features/pos/pos_checkout_security_migration_test.dart` checks that the August migration contains a revoke statement. It does not check effective permissions after October migrations. That explains why a migration-text assertion alone cannot detect this later grant regression. Add execution-based grant/role tests in an isolated database when implementation is authorized; do not claim existing tests failed or passed because they were not run here.

## 2. Photo privacy requires a coordinated client and storage change

Related findings: SEC-01 and SEC-06, [initial audit](security_read_only_audit.md).

### Proposed design

1. Introduce a shared photo reference/resolver that can distinguish legacy URLs, canonical storage object references, and unsynced local files.
2. Convert only known trusted project/bucket URLs into object references. Do not fetch arbitrary user-supplied URLs server-side or attach authorization headers to untrusted hosts.
3. Resolve authorized storage objects to authenticated downloads or short-lived signed URLs at display time. Never persist expiring URLs as permanent record identifiers or place service credentials in the client.
4. Update thumbnails, gallery, full-screen previews, upload, ticket serialization and offline sync together. Keep support for old stored references while reading through the protected resolver.
5. Verify all supported deployed clients are ready, then change bucket visibility and current-membership policies in a coordinated release.
6. Confirm unauthenticated previously distributed links no longer serve through the protected origin, and inspect provider cache behavior. Previously downloaded copies cannot be remotely recalled.

### Important compatibility boundary

An unchanged client that requires unauthenticated public image URLs cannot simultaneously retain that behavior and enforce private authenticated access at the same URLs. Keeping public access as a fallback defeats the fix. This requires a supported-client upgrade/cutover decision, not an undocumented breaking toggle.

### Regression criteria

- Existing saved URL, new upload and unsynced local file all display for authorized users.
- Wrong-tenant, revoked and unauthorized-branch users cannot obtain/read protected photos.
- Expired display URLs refresh through authorization; they are not saved back as permanent paths.
- Offline upload retry preserves the local photo and does not lose a ticket or create uncontrolled duplicate objects.
- Current Android/Windows/iOS repair flows and intended web flows are tested separately where supported.

The existing photo test covers serialization and source wiring. It does not demonstrate private object retrieval or authenticated image loading.

## 3. Policies must preserve legitimate direct-write workflows

### Inventory prices

Audit both the legacy RPC and direct `products.sale_price` updates. The current bulk editor calls `_requireFeature('inventory.bulk_pricing')`, filters products locally, and updates products directly. A client feature check cannot authorize a raw API request. Apply agreed price-edit and branch permissions at database/server boundaries, while retaining intended manual pricing and offline synchronization. Baseline product policies are incomplete in the repository and need a deployed export before selecting exact SQL changes.

### Repairs and returns

List each field and state transition the existing repositories write. Separate harmless editable fields from approval, financial, ownership and lifecycle fields. Then choose field restrictions, invariant triggers or atomic RPCs with a compatible client transition. Avoid a blanket “revoke all writes” patch against a client that still upserts returns or repair tickets.

For returns, test item delete/reinsert retries, already-approved records, partial returns and cash/credit ledger posting. Any redesign should avoid leaving the parent updated with missing items after a partial network failure; establish that separately with runtime tests before claiming atomicity.

### Shared authorization helpers

Build a caller matrix before tightening `current_user_tenant_id`, permission and branch helpers. Positive controls must include owner, manager, cashier, explicitly assigned branch staff and supported legacy staff. Negative controls include disabled users, revoked roles and revoked selected branches. Legacy behavior needs an explicit supported policy; it must not silently restore permissions after revocation.

## 4. Rollout gates for any future approved fix

1. **Read-only deployed comparison:** Confirm source findings exist in the actual environment and identify supported clients.
2. **Isolated implementation:** Work on a separate branch with synthetic test fixtures. No production writes or test impersonation.
3. **Compatibility proof:** Compare baseline allowed flows and rejected adversarial requests across supported client versions. Include offline queue and retry cases.
4. **Concrete review:** Present exact diff/migration, affected clients, test evidence, unresolved limitations and deployment steps. Current user restriction requires explicit approval before implementation changes; deployment must remain within authorized scope too.
5. **Controlled deployment:** Use a compatible release sequence and monitor authorization failures, checkout failures, image failures and sync backlogs.
6. **Safe recovery:** Stop rollout or use a reviewed forward correction. Do not reopen the known bypass/public bucket as an automatic rollback. Preserve queued transactions and user data; if no secure compatible fallback exists, pause the affected feature rather than silently grant unauthorized access.

## 5. Status and the next dependency

Completed now: source caller mapping, compatibility hazards, recommended change order and regression acceptance criteria. No remediation or tests were performed.

Live classification still needs a securely configured authorized read-only connection or sanitized catalog export. Prepared queries are in [Live Security Verification](security_live_verification.md). Until evidence arrives, source-level risk and compatibility planning can continue, but live safety and exact deployment steps cannot be certified.

Recommended order: verify legacy checkout and photo visibility first; then disabled/branch revocation helpers and direct-write policies; then account/cache/operational hardening. Preserve evidence for every step in the original [production plan](production_security_plan.md).
