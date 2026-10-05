# Supabase metadata verification — supplied deployment snapshot

Reviewed: 2026-10-05. Snapshot collected: **2026-10-05 15:27:01 Asia/Karachi** (10:27:01 UTC).

Evidence: user-supplied `Pasted text.txt`, attachment `a23378d0-e1b1-4354-b203-bf6e49487786`.
SHA-256: `a52334f3c65bdc344ee63c8d535331bdd085c7f7f47ea4d3bb959af9a7c5ec4f`.

The JSON parsed successfully: 118 policies, 90 relations, 696 function/role privilege entries (232 function signatures across three roles), 14 selected function definitions, 590 constraints, and 74 non-internal triggers. The export reports `transaction_read_only = on`. It does not identify the project/environment, so conclusions apply to the supplied snapshot, assumed by the user to be the intended project. This is not a direct connection or proof of the current state after collection.

No application code, migrations, database settings or records were changed. No application endpoint or mutation was exercised. Documentation only was added/updated.

## Important corrections to the earlier source audit

1. **SEC-09 is NOT an active direct legacy-checkout exposure in this snapshot.** `commit_pos_sale(jsonb)` has `execute=false` for both `anon` and `authenticated`. The v2 wrapper is executable by authenticated users; its unvalidated implementation is not. The source migration can reintroduce a grant if applied later, but the snapshot does not show that grant. Do not apply a speculative legacy-endpoint fix to solve an already-closed route.
2. **SEC-05 and SEC-10 are not present as those RPCs in this snapshot.** Neither `product_has_active_imei_units` nor `bulk_update_product_prices` appears among public function signatures. No deployed exploit through those named functions is established. Current direct product updates remain a separate concern.
3. All **80 exported public base tables** have RLS enabled. The two public views show `security_invoker=true`; absence of table RLS on those views is not itself a missing-RLS vulnerability. Policy quality and privileged function behavior remain material.

## Priority findings established by metadata

### SEC-16 — NULL tenant can skip the shared branch authorization guard

**Priority: High, first isolation-test priority; potentially cross-tenant.** The defect is in the exported function body. End-to-end exploitability depends on an active owner profile with a NULL tenant being reachable; no user records or attacks were queried.

`current_user_has_branch_permission(uuid,uuid,text)` rejects a caller using:

```sql
if v_actor.id is null
   or v_actor.tenant_id <> p_tenant_id
   or not v_actor.is_active
   or v_actor.deleted_at is not null then
  return false;
end if;
```

It then checks that the requested branch belongs to the requested tenant, and returns true immediately when `v_actor.role = 'owner'`.

For an existing active, non-deleted owner whose tenant is NULL, comparing that NULL tenant with a target tenant yields UNKNOWN rather than TRUE. The rejection condition is therefore NULL, and PL/pgSQL does not enter the rejection branch. A valid target tenant/branch pair then reaches the owner shortcut. This is a deterministic consequence of the exported logic, not a claim of observed attacker activity. [PostgreSQL comparison semantics](https://www.postgresql.org/docs/current/functions-comparison.html), [PL/pgSQL conditional behavior](https://www.postgresql.org/docs/current/plpgsql-control-structures.html)

The snapshot's onboarding INSERT policy explicitly describes an owner with NULL tenant. A `users_protect_client_insert` trigger is installed; its actual definition and column nullability were not included in the export. The repository version of that trigger allows the owner-without-tenant onboarding state. Confirm deployed behavior before labeling the full path reproduced.

**Reach:** Exported accounts policies delegate SELECT/INSERT/UPDATE/DELETE to this helper. `account_transactions`, repair financial events/parts/payments also use it for reads. Authenticated table privileges are available. Its definer owner has `BYPASSRLS=true`. A row-based SELECT policy supplies target tenant/branch values itself, so knowing foreign UUIDs is not necessarily required to expose rows if the onboarding profile condition holds.

**Proposed correction, not applied:** Require non-NULL actor/target tenant and branch, use NULL-safe tenant comparison (`IS DISTINCT FROM`), and reject inactive/unknown account state explicitly before any owner shortcut. Test incomplete onboarding, missing profile, matching owner, wrong-tenant owner, disabled owner, staff and revoked assignments. Preserve normal onboarding by denying business access until membership is complete; do not remove onboarding itself.

**Evidence still needed:** Deployed `users.tenant_id` nullability, insert/compatibility trigger definitions, and an isolated synthetic onboarding test. Do not run cross-tenant requests using real customer data to validate this.

### SEC-17 — Direct sales/product/inventory access remains broad despite protected checkout RPC

**Priority: High; deployed permission configuration confirmed.** `sales`, `sale_items`, `sale_payments`, `products`, and `inventory` all have authenticated CRUD grants and permissive FOR ALL policies scoped to tenant (or a branch belonging to that tenant), without current per-action or assigned-branch checks.

Examples from the export:

- `Tenant can manage own sales`: permits rows whose branch belongs to the user's tenant.
- `Tenant can manage own products`: permits rows matching the user's tenant.
- `Tenant can manage own sale items/payments`: follows the parent sale's tenant.

No additional restrictive policies on these tables were exported. No custom triggers were exported for `sales`, `sale_payments`, `products`, or `inventory`; sale-items has two cost/line-total triggers whose bodies were not included. Database constraints still apply.

**Impact:** Closing the legacy RPC does not close direct table reads/writes. Same-tenant staff may access other branches or mutate financial/inventory rows without checkout action checks. Exact accepted payloads and downstream ledger effects remain untested; this is not a claim that every mutation succeeds or that tenant filtering is absent.

**Proposed correction:** Build a field/action matrix and protect direct paths as well as RPCs. Existing clients use direct product updates and return/repair synchronization, so blanket CRUD revocation is not an approved compatible fix. Use narrowly authorized policies/field restrictions or a staged server-operation migration, backed by positive native-client tests.

### SEC-01 — Public repair-photo configuration confirmed

`bucket_flags` contains `repair-photos: public=true`; `expense-receipts: public=false`. This confirms the public-photo configuration from the source review. It does not prove any particular photo exists or was downloaded. Public asset delivery requires a coordinated private-access client transition described in [the compatibility plan](security_compatibility_rollout.md).

### SEC-03/04/06 — Revocation gaps confirmed in exported definitions

- Tenant lookup and global permission helpers omit active/deleted-user checks. Their owner is `postgres` with BYPASSRLS, so the users table's restrictive active-row policy does not repair those privileged lookups.
- The older branch-access helper checks selected `users.branch_id`, not current role assignment. Exported branch-role mutation does not clear that selected branch; trigger bodies beyond the selected definitions need final review.
- Repair-photo policies still include an alternate `app_metadata.tenant_id` OR branch without current account-state checks. Impact depends on tokens containing that metadata.

These are confirmed control gaps, conditional on the relevant account/token states; no disabled account or token was used to exercise them.

## Disposition of all earlier findings

| Finding | Snapshot classification | Remaining limit |
| --- | --- | --- |
| SEC-01 public photos | Confirmed public bucket | No object retrieval performed |
| SEC-02 procurement branch/action gap | Confirmed broad policies plus authenticated grants | Specific writes/trigger effects not tested |
| SEC-03 disabled-account helpers | Confirmed bodies and privileged owners | Account/session population not inspected |
| SEC-04 selected-branch revocation | Confirmed helper/mutation pattern | Other trigger bodies and runtime test pending |
| SEC-05 IMEI oracle RPC | Not present among exported public functions | Source/deployment drift unresolved |
| SEC-06 photo metadata fallback | Confirmed policy predicates | Token claim population unknown |
| SEC-07 PIN request budget | No attempt budget in exported function | External rate controls not exported |
| SEC-08 invite error disclosure | Not covered by database export | Deployed Edge Function source unknown |
| SEC-09 legacy checkout grant | Direct route blocked for anon/authenticated | Future source migration regression still needs prevention |
| SEC-10 bulk-price RPC | Not present among exported public functions | Direct product-write path covered by SEC-17 |
| SEC-11 repair/inventory-unit policies | Confirmed broad policy/grant configuration | Mutation impact not executed |
| SEC-12 returns | Confirmed broad policy/grant configuration | Refund RPC controls must be considered separately |
| SEC-13 buy-in | Confirmed tenant-only policies, independent FKs, no custom trigger exported | Sensitive records not read; no test insert |
| SEC-14 persistent cache | Not covered by database export | Client behavior remains source-only |
| SEC-15 repair retry ordering | Confirmed exported body returns before authorization | No runtime response-oracle test |
| VERIFY-01 admin MFA | Admin membership guard present; no inline AAL2 check | Provider MFA policy unknown |
| OPS-01 migration drift | Snapshot differs from repository; migration-history table unavailable | Applied version history cannot be collected from that table |

## Other interpretation safeguards

- Legacy permissive users INSERT/UPDATE policies remain, but insert/update protection triggers also exist. Do not claim arbitrary self-promotion solely from the permissive policies without inspecting those triggers.
- Several tables retain anonymous CRUD grants; this is excessive privilege to review, not proof of public data exposure where RLS still denies rows.
- A missing `WITH CHECK` on an applicable UPDATE/ALL policy can inherit its USING condition. It is not automatically an unrestricted-write policy.
- Platform-admin helper checks active platform membership. This export alone does not establish all caller function bodies, provider MFA enforcement, or admin session compromise resistance.
- Function presence/grants do not establish exposed API schema configuration. Table/function configuration is verified here, network reachability is not.

## Recommended next work without changing existing applications

**Update:** The supplemental export has now been received and reviewed; see the follow-up section below. Do not request the same export again. Isolated reproduction and remediation remain unperformed.

1. Collect the small supplemental metadata export in `security_metadata_followup.sql`: onboarding trigger definitions, user-column nullability, active branch-revocation trigger definitions and migration versions.
2. Reconcile this snapshot with repository migration history before preparing any production SQL. Do not rerun all migrations to make them match.
3. Prioritize an isolated test of SEC-16, then direct-table permission tests (SEC-17), and photo-access compatibility. The user has not authorized remediation; no implementation changes are included here.
4. Present a concrete backward-compatible patch and its synthetic regression evidence only after the required implementation/test authorization. Deployment is not implied by metadata sharing.

**Conclusion:** The export resolves several uncertainties and corrects the legacy-checkout warning, but it does not support a production-ready security claim. The NULL-tenant helper and direct table authorization deserve priority over changing an already-restricted legacy RPC.

## Follow-up received — onboarding condition confirmed in deployed metadata

**Subsequent isolated validation:** [SEC-16 test result](security_sec16_test_result.md) records a reproduced cross-tenant read on synthetic accounts and 25 passing candidate checks. This supersedes earlier statements that no isolated reproduction exists; production remains untouched.

Reviewed 2026-10-05. Evidence: attachment `632fda18-6c77-48f3-94a0-9214081a8228`, `Pasted text.txt`.
SHA-256: `898256e41a9577ee6f9bd8ae4acdb477109460a1351cd2d942436443208e5a7f`.
This supplemental export has no collection timestamp or project identifier; association with the first snapshot is based on the user's supplied context.

### SEC-16 status update

The previously uncertain onboarding precondition is supported by the deployed metadata:

- `users.tenant_id` and `users.branch_id` are nullable; `id`, `role`, and `is_active` are not nullable.
- Deployed `protect_user_client_insert()` explicitly accepts the caller's own owner profile with NULL tenant/branch and rejects non-NULL tenant/branch on initial client insertion.
- `ensure_compatibility_user_role()` immediately returns for NULL tenant; it does not reject or fill that tenant during onboarding.
- `block_direct_tenant_detach()` restricts changing an existing non-NULL tenant to NULL. It does not prevent initial NULL-tenant profiles.
- The branch-selection trigger only covers branch updates and does not repair the permission helper's comparison.

**Classification: confirmed authorization logic defect in the supplied deployed configuration, with a supported onboarding state.** An active owner awaiting shop setup can pass the shared helper's owner shortcut for a foreign tenant/branch because NULL inequality does not trigger rejection. Actual API access, account creation settings, affected data, and exploit execution have NOT been tested. Do not describe this as an observed compromise.

The existing accounts and account-transaction policies delegate to this helper, making the defect security-relevant beyond a harmless boolean RPC. A role assignment is not required to reach its owner shortcut. This deserves the first isolated regression test and narrowly scoped remediation proposal.

### Concrete minimal correction for review — NOT applied

Replace only the initial rejection guard inside `current_user_has_branch_permission` with explicit missing-state rejection and NULL-safe comparison, preserving the remainder of the function initially:

```sql
if v_actor.id is null
   or v_actor.tenant_id is null
   or p_tenant_id is null
   or p_branch_id is null
   or v_actor.tenant_id is distinct from p_tenant_id
   or v_actor.is_active is not true
   or v_actor.deleted_at is not null then
  return false;
end if;
```

This is a proposed fragment for the existing function, not a standalone SQL command and not an applied migration. It keeps initial profile creation possible while denying business authorization until the user has a tenant. Preserve the current signature, ownership, grants, branch-existence check, owner behavior within the correct tenant, and staff role/override logic. Do not claim overall production readiness from this one correction.

Before implementation/deployment, establish the baseline using a disposable database and synthetic accounts. Required outcomes:

| Fixture | Expected helper/resource access |
| --- | --- |
| No authenticated profile | Denied |
| Active onboarding owner with NULL tenant | Denied for every business tenant/branch |
| Active owner in tenant A requesting tenant B | Denied |
| Active owner in tenant A requesting its valid branch | Existing intended access preserved |
| NULL target tenant/branch | Denied |
| Disabled/deleted owner | Denied |
| Staff with an assigned permitted branch/action | Existing intended access preserved |
| Staff with revoked assignment or denied action override | Denied |

Exercise both the helper and table policies for accounts/account transactions with synthetic records. Verify normal signup/setup and existing native-client workflows still work. No real customer data or production identity impersonation is needed.

### SEC-04 and migration-history updates

The deployed revocation cleanup only deletes permission overrides. It does not clear selected branch. The deployed selection trigger returns early when branch is unchanged. This strengthens the selected-branch revocation finding for older-helper callers; no runtime test was performed.

`migration_history_available=false` is reconfirmed. Do not query the nonexistent history table again or create it as part of this audit. Schema/function definitions, not assumed applied migration versions, must anchor any proposed change.

**Current boundary:** Metadata review is complete for these follow-up questions. Existing code and database remain untouched. The user previously required explicit approval before implementation changes; receiving exports does not revoke that restriction. Next work is an authorized isolated fix/test effort, not another repeated metadata request.
