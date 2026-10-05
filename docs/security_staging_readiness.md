# Three-candidate staging readiness

Date: 2026-10-05. Status: local combined SQL regression complete; real application compatibility NOT tested; NOT deployed.

## Plain-language explanation

Staging is a separate testing copy of the app/backend containing fake shops and records. It allows mobile/desktop verification without experimenting on the live shop database. The current isolated PostgreSQL harness is useful evidence but is not that complete app copy.

The user has not confirmed a separate Supabase test project or test-app configuration. Do not interpret this as permission to modify the production project, register a paid service, or change current application connection settings.

## Completed in this step

- Bundled SEC-16 (NULL-tenant authorization), SEC-03 (disabled/deleted account helpers), and SEC-04 (revoked selected branch) into one review-only transaction outside the application repository.
- Ran all three candidates together on an in-memory PostgreSQL fixture: **30 checks passed**. The suite includes prior SEC-16 cases and new interaction checks for supplier policies, revoked branch access, disabled global-role holders and legacy compatibility. It is not 30 new independent app flows.
- Generated a direct policy dependency map from the supplied database export. Source scans also show shared helpers in procurement, mobile services, accounts, POS, repairs, reporting and role management, so verification must extend beyond one screen.

Artifacts:

- [Combined candidate SQL — not deployed](../../security-review-null-tenant/staging-candidate.sql)
- [Combined executable tests](../../security-review-null-tenant/all-candidates-test.mjs)
- [30-check results](../../security-review-null-tenant/all-candidates-results.json)
- [Exported policy dependency map](../../security-review-null-tenant/policy-dependencies.md)

No changes to app source, existing migrations, connection configuration or live Supabase. New documentation and isolated candidate artifacts only.

## Requirements for real app testing

1. Separate test Supabase project with authorized access and an accurate schema/functions/policy baseline. Existing migration history is absent and repository differs from deployment; do not blindly replay every migration or assume the metadata export is a restorable database backup.
2. Synthetic tenants A/B, branches, active owner/staff, disabled staff, revoked branch assignments, incomplete onboarding and legacy staff. No customer CNICs/photos or real payment data.
3. Separate app checkout/build configured for the test backend, visibly marked TEST. Keep the user's current app configuration untouched. Verify compiled URLs/project identity before login or writes.
4. Test-device/platform selection based on currently supported installations. Existing native mobile/Windows flows and future iPhone web flows are distinct: a web build/device compatibility result cannot be inferred from the SQL suite.
5. Apply candidate only in the confirmed testing environment after baseline comparison. Preserve function owners/ACLs. Do not automatically roll back to vulnerable guards.

## App regression checklist — all pending

| Area | Authorized flow to preserve | Denied/error behavior to check |
| --- | --- | --- |
| Login/setup | Owner signup, shop setup, reconnect, normal login | Incomplete owner sees no business data from other shops |
| Branches | Owner switching, assigned staff selection, documented legacy behavior | Revoked selected branch stops granting access without restart |
| POS | Cash/credit/mixed checkout, receipt, refund, retry | No unauthorized action; no duplicated stock/payment/ledger effects |
| Inventory/procurement | List/edit allowed products, suppliers, receipt/payment | Cross-shop/disabled access denied; intentional permissions retained |
| Repairs | Ticket display/update, parts, payment, cancellation | No inappropriate permission fallback |
| Accounts/reports/mobile services | Authorized ledgers, transfers, reports, provider transactions | Denied role/branch state does not expose financial data |
| Staff management | Authorized invitation and role operations | Disabled manager denied by backend |
| Offline sync | Supported queued sale/repair/procurement replay | Revoked-user work handled explicitly; not silently lost |

Record client version, platform, test fixture, before/after results, failures, and final server/local records. SQL tests passing does not mark this checklist complete.

## Next decision

Explain staging before asking for project details. If no separate test project exists, prepare its setup with the user and secure configuration without asking for passwords/service keys in chat. Live rollout remains blocked on app-level verification and explicit deployment authorization. Other audit findings (public photos, broad action policies, etc.) remain unresolved after these three candidates.
