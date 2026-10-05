# Production Security Plan — Apple Web App

Date: 2026-10-05 (Asia/Karachi)
Status: Proposed implementation and verification plan. No security certification, completed audit, or production readiness claim.

Interview and system-design explanation: [Threats, Solutions, Implementation, and Interview Answers](security_system_design_interview.md).

## 1. Objective and limits

Primary requirement: changing a URL, object ID, request body, query filter, browser state, or API call must never grant access beyond the authenticated user's current permissions. This includes a technically skilled attacker calling Supabase directly without using the application.

No system can honestly guarantee 100% security or uninterrupted availability. Our release decision will instead require documented controls, passing adversarial tests, independent review, and operational recovery evidence. A discovered authorization bypass blocks release regardless of its assigned severity.

iPhone, iPad, and macOS are the supported devices. Device detection is a product restriction, not proof of identity or a security boundary. Spoofing that detection must not weaken backend controls.

This document describes what WILL be implemented and how it WILL be verified. It does not claim those changes have already been made. Implementation results will be recorded separately using the evidence template in section 13.

## 2. Current repository observations

Limited read-only inspection found:

- Flutter frontend with Supabase, Drift/local storage, and an existing web manifest.
- SQL migrations and security tests in `supabase/migrations/` and `supabase/tests/` covering tenants, branches, roles, sensitive fields, and account lifecycle.
- `lib/core/authorization/supabase_permission_data_source.dart` loads remote permissions and can fall back to cached permissions. This needs explicit offline/revocation review; it is not proof of a vulnerability by itself.
- `supabase/functions/invite-staff/index.ts` validates a caller, invokes invitation RPCs, and uses a service-role client for privileged steps. It currently has wildcard CORS and returns underlying error details/stage. Review authorization, input limits, error disclosure, retry/concurrency behavior, and cleanup ownership. Wildcard CORS alone does not establish unauthorized access.
- `20260809000300_secure_pos_checkout_and_discount_approval.sql` includes privileged SQL and approval PIN handling. Verify execution grants, authorization, safe object resolution, brute-force controls, and all alternate write paths.
- Native `dart:io` usage exists in business flows; browser compatibility and security need verification together.

Live Supabase policies, deployed functions, hosting settings, secrets, backups, and migration drift have NOT been verified. Existing test files have NOT been executed as part of this planning task.

## 3. Threat model and trust boundaries

Treat all browser inputs as attacker-controlled, including tenant IDs, branch IDs, role labels, prices, subscription flags, device headers, and locally cached permissions. Assume an attacker can discover frontend code, public API keys, endpoint addresses, and valid object IDs.

Actors to test: anonymous caller, valid user from another shop, same-shop staff with fewer permissions, branch-restricted staff, disabled/deleted user, revoked role holder, expired subscriber, and compromised administrator session.

Assets: customer details, inventory/IMEIs, sales, payments, repairs/photos, accounting, staff roles, subscriptions, exports, credentials, and service availability.

Authorization decision for each operation:

1. Validate authenticated identity using trusted token verification.
2. Load current server-side account activity and membership.
3. Resolve the target object's actual tenant and branch from stored data.
4. Check the required action permission and applicable subscription entitlement.
5. Validate all related objects and allowed field changes.
6. Execute only the authorized operation, atomically where necessary.

Missing identity, missing permission, or failed security lookup means deny. Infrastructure errors must not silently become permission grants.

## 4. Phase A — Inventory and access policy specification

Create an inventory of every exposed table, view, RPC, Edge Function, storage bucket, Realtime channel, export, auth callback, and admin route. Include the admin portal and direct Supabase endpoints, not just Flutter routes.

For each surface record: purpose, allowed roles/actions, tenant/branch scope, sensitive fields, input schema, authentication method, grants/RLS, privileged execution, abuse controls, and test ID.

Define an access matrix from existing product rules. Do not accidentally remove legitimate tenant-wide operations; document their authorized roles and explicit scope. Separate platform administration from shop-owner authority. Users must not assign themselves tenant membership, owner/platform roles, billing state, or additional branches.

Inspect applied database definitions and grants read-only when environment access is available. Compare them with migrations. Build a disposable database from migrations and identify ordering/collision issues before making production changes.

Deliverables: surface inventory, access matrix, prioritized gap register, and migration/deployment comparison. No live secrets or real customer data in reports.

## 5. Phase B — Prevent URL and direct API authorization bypass (P0)

### B1. Row and field access

Enable and verify RLS for every exposed business table. Audit SELECT, INSERT, UPDATE, and DELETE separately, including UPDATE ownership checks and INSERT tenant/branch checks. Review combined permissive policies, restrictive policies, grants, views, and any bypass behavior.

Use current authenticated identity and server-maintained membership for authorization. A supplied tenant ID may narrow an authorized query; it must never establish membership. Test requests with the filter removed entirely.

Prevent sensitive field changes through column grants, narrow validated RPCs, or equivalent server constraints. RLS alone does not define which fields a user may edit. Protect role, tenant, subscription, ownership, approval PIN/hash, and administrative fields from both unauthorized writes and reads where appropriate.

Check parent-child relationships: an invoice line cannot reference another tenant's invoice/product; a payment cannot point to another shop's account. Enforce valid relationships through composite constraints and/or transactional server validation.

### B2. Functions, privileged code, and alternate paths

Audit every RPC's execute grants, caller identity, object scope, and input validation. Prefer invoker privileges where practical. For necessary SECURITY DEFINER functions, use controlled ownership, explicit grants, a safe search path with schema-qualified references, and explicit authorization inside the function.

Keep service-role credentials only in server-controlled environments. A service-role operation bypasses RLS, so establish authorization and scope before using it. Prefer user-scoped clients for normal operations. Review invitation completion/failure/cleanup so one request cannot affect unrelated accounts, including retries and partial failures.

Business operations such as checkout/refund must not be bypassable with direct table writes. Remove unnecessary write grants or enforce the same invariant in database constraints/triggers. Inspect old RPC versions and alternative endpoints, not only the preferred route.

### B3. Links and files

Changing `/invoice/A` to `/invoice/B` must yield no unauthorized content or mutation. UUIDs and hidden routes are not authorization. Use consistent forbidden/not-found responses without leaking record details; direct RLS reads may safely return no rows.

Keep private storage private and enforce object ownership for upload, read, replace, list, and delete. Issue download links only after authorization. Signed URLs are bearer capabilities that can be forwarded until expiration; use short lifetimes and an authenticated download endpoint where immediate revocation is required. Public sharing is off by default until an explicit business requirement defines its scope.

Validate invitation/reset destinations against exact approved redirects. Expired/used tokens must fail. Never put service secrets or reusable login credentials in URLs or logs.

Deliverable: reviewed migrations/functions with executable allow AND deny tests. Completion requires proof against direct APIs as well as normal UI navigation.

## 6. Phase C — Accounts, sessions, and Apple restriction

- Require MFA for platform administrators and privileged shop users; verify elevated assurance on sensitive backend actions, not only in the UI.
- Add login/reset/invitation/PIN abuse controls with generic external errors. Avoid account enumeration and easy attacker-triggered permanent lockouts.
- Enforce disabled-user and revoked-membership checks in all relevant backend paths. Cached role data may help render UI but cannot authorize server operations.
- Define token lifetime and revocation behavior. Supabase sign-out does not immediately invalidate an already issued JWT. For required immediate revocation, verify server session validity or a server-maintained revocation/version marker through every protected path, including RPC and file access. Test old-token replay explicitly.
- Recheck current permission during offline synchronization. Queue entries from revoked users must fail safely; do not replay them with elevated credentials.
- Apply Apple-device detection at supported entry points and show an unsupported-device screen elsewhere. Keep every security check active after spoofing the device header. Do not claim tamper-proof device attestation for a public PWA.

## 7. Phase D — Browser, offline data, and uploads

Use HTTPS and deploy tested security headers: CSP compatible with the actual Flutter build, anti-framing policy, MIME protections, and appropriate referrer/permissions policies. Validate HSTS scope before enabling it for all subdomains. Restrict third-party scripts and review any HTML/JavaScript interop for XSS.

Document session storage architecture before implementation. With browser-held bearer tokens, minimize script exposure and protect against XSS. If cookie sessions are introduced, use Secure/HttpOnly/SameSite settings plus appropriate CSRF/origin checks. CORS is browser policy, not authentication; command-line clients can ignore it.

Cache application assets separately from private records. Never put authenticated API responses in a shared CDN cache. Partition local data by account/tenant, clear sensitive caches on logout/account switching, and test back-button and service-worker behavior. Browser storage encryption with a key stored beside the data is not a complete security boundary.

For the initial web release, prefer online authorization for financial writes and a minimal offline cache. Any required offline sales mode needs its own bounded-access policy, conflict handling, and explicit revocation limitations. Data already downloaded to an offline or compromised device cannot be remotely guaranteed erased.

Validate file size, type, actual content, and access scope. Use generated object paths, prevent overwrite across tenants, and reject or isolate active HTML/SVG content. Bound CSV import size/rows and address spreadsheet formula injection in exports.

Deliverable: iPhone/iPad installed-web-app and Mac browser verification, including account switching, cache cleanup, uploads, and auth redirects.

## 8. Phase E — Abuse resistance and financial integrity

Use Cloudflare protection for traffic actually routed through it. The public Supabase origin is a separate entry point; frontend hosting protection does not automatically cover that traffic.

For each endpoint, choose and document direct RLS-protected access or a controlled server endpoint. For expensive operations requiring a gateway, remove equivalent public execution/write paths or enforce the same limits there. Hiding an origin or relying on CORS does not prevent bypass. Preserve existing native-client compatibility deliberately and deploy coordinated changes if required.

Enforce durable, atomic limits across instances, with per-IP, per-account, and per-tenant budgets as appropriate. Include login, PIN verification, invites, exports, bulk imports, uploads, report queries, and Realtime subscriptions. Set numeric limits after measuring representative usage; record limit values, time windows, burst allowance, and legitimate-user impact before launch. Return controlled retry behavior instead of unbounded retry loops.

Bound query/result size, pagination, statement duration, request size, export concurrency, and background-job duration. Index actual access patterns. Measure database load and bandwidth, not only registered user counts. Configure spending alerts and review which costs any provider cap does and does not cover.

For sales/payments/refunds: server-validate totals and authorized manual-price/discount workflows, enforce atomic changes, use scoped idempotency keys with database uniqueness, reject a reused key with a different payload, and test concurrent stock/payment updates. Client retries must not duplicate accounting entries. If payment webhooks are used, verify signatures and replay protection server-side.

Deliverable: controlled staging load/abuse report, configured limit register, and transaction/concurrency evidence. Do not perform denial-of-service testing against production.

## 9. Phase F — Operations and recovery

Enable MFA and least privilege for domain, DNS, hosting, Supabase, source-control, and CI accounts. Protect domain renewal/recovery and registrar changes. Separate production from test credentials and data. Scan code/build artifacts/logs for leaked secrets; rotate any confirmed exposed credential without putting its value in documentation.

Record security-relevant events with actor, tenant, target, action, result, UTC timestamp, and correlation ID. Keep logs access-controlled and resistant to normal-user modification. Exclude passwords, PINs, tokens, and unnecessary customer details. Define retention and deletion policy.

Monitor uptime, error/denial spikes, unusual logins, query latency, resource usage, job failures, backup failures, and spend. Assign a real alert recipient and incident owner before launch.

Define recovery objectives before selecting backups: provisional target RPO <= 1 hour and RTO <= 4 hours, subject to measured restore capability and budget approval. These are targets, not existing guarantees. Daily backups alone cannot meet a one-hour RPO. Include object storage, configuration, and secrets recovery; database backups alone are insufficient. Test restoring into an isolated environment and record measured results. If targets cannot be met, document the actual recoverable window before onboarding real business data.

Prepare runbooks for leaked keys, compromised accounts, suspected cross-tenant access, abusive traffic, failed deployments, and provider outages. Include containment, session revocation, safe credential rotation, recovery verification, and customer communication responsibility. Prefer backward-compatible migrations and reviewed forward fixes; do not rollback by silently removing security protections.

## 10. Required adversarial test matrix

Use synthetic fixtures: two tenants, multiple branches, owner/manager/cashier/read-only roles, disabled users, revoked assignments, and expired entitlements. Execute against disposable/staging environments with production-equivalent settings.

| ID | Attempt | Required result |
| --- | --- | --- |
| AUTH-01 | Change another tenant's record ID in route/query/body | No unauthorized data or write |
| AUTH-02 | Remove tenant filters; request lists/counts/exports directly | Only authorized scope; no aggregate leaks |
| AUTH-03 | Read/write another branch using same-tenant staff | Denied unless explicitly allowed in access matrix |
| AUTH-04 | Change own role, tenant, subscription or sensitive profile fields | Denied; stored authority unchanged |
| AUTH-05 | Invoke RPC directly or use alternate table writes | Same permissions and invariants enforced |
| AUTH-06 | Mix foreign parent/product/customer/account IDs | Atomic rejection; no partial mutation |
| AUTH-07 | Reuse token after disabling user/revoking access | Protected paths reject under documented revocation policy |
| AUTH-08 | Anonymous/forged/expired token; edited JWT claims | No protected access |
| AUTH-09 | Guess/list/overwrite private storage objects | No unauthorized access; no cross-tenant overwrite |
| AUTH-10 | Subscribe to other tenant's Realtime events | No event/payload leakage |
| AUTH-11 | Modify cached permissions or sync after revocation | Server rejects unauthorized actions |
| AUTH-12 | Open platform-admin routes as shop owner | No platform-level access |
| AUTH-13 | Reuse/alter invite, reset, or download links | Scope/expiry enforced; no redirect takeover |
| AUTH-14 | Repeat an allowed operation | Positive control succeeds; security does not break valid workflows |
| INT-01 | Double-submit/retry sale, refund, or payment concurrently | One intended financial effect; consistent stock/ledger |
| ABUSE-01 | Flood costly endpoint; repeat through direct origin | Bounded resource use; no bypass of required limits |
| WEB-01 | Logout/account switch/back button/offline cache | No previous account's private data shown by app |
| WEB-02 | Upload malicious/oversized file; inject rendered input | Rejected or safely rendered; no script execution |
| OPS-01 | Restore backups and recover a failed release | Measured recovery meets declared objectives |

Check both response and resulting database/storage state. A returned error is insufficient if the mutation already happened. Static tests searching migration text do not replace executing authorization tests as real roles or direct HTTP clients.

## 11. Release gates

Production readiness requires all of the following, with evidence attached:

1. Complete surface inventory and approved product access matrix; no unreviewed privileged endpoint.
2. Passing negative and positive authorization tests, including direct Supabase requests and every table/RPC/storage path used by the app.
3. No unresolved authorization bypass, exposed privileged secret, or critical/high security finding. Lower-severity exceptions need owner, rationale, expiry, and remediation date.
4. Applied production policies, grants, functions, and configuration match the tested release; migrations rehearsed safely and deployed with a compatible client sequence.
5. Session revocation, cache isolation, financial replay/concurrency, and Apple browser tests pass.
6. Representative load test passes predefined latency/error budgets; rate limits and bypass resistance verified. Exact targets must be recorded before the test.
7. Monitoring delivery and restore/rollback runbooks tested; recovery objectives declared honestly.
8. Independent security review of authorization and privileged flows, followed by retesting findings. Target applicable OWASP ASVS 5.0 Level 2 requirements with a recorded requirement-to-evidence mapping; do not claim certification from a checklist alone.
9. Limited pilot with monitoring, then staged expansion. Security checks continue after launch and after changes to roles, queries, migrations, or dependencies.

No production-ready label until these gates are satisfied. Deployment access, provider capabilities, independent-review arrangements, and recovery budget remain implementation dependencies; they do not prevent documenting or performing local audit work.

## 12. Execution order and deliverables

| Order | Work | Output |
| --- | --- | --- |
| 1 | Inventory and policy audit | Access matrix, trust map, gap register |
| 2 | Close authorization bypasses | Reviewed SQL/functions and direct-access tests |
| 3 | Sessions, offline behavior, financial integrity | Revocation, isolation, transaction test evidence |
| 4 | Browser hardening and abuse controls | Config changes, limit register, staging reports |
| 5 | Operations and independent review | Recovery exercise, alerts, reviewed findings |
| 6 | Production verification and pilot | Release checklist, configuration comparison, pilot report |

Do not estimate a completion date before the inventory and migration rehearsal establish scope. Track each item as Planned, Implemented, Verified in staging, or Verified in production; never equate code committed with protection deployed.

## 13. How we will explain what was implemented

For every control maintain this record in a separate implementation report:

| Field | Required content |
| --- | --- |
| Control/test ID | Stable reference such as AUTH-01 |
| Problem | Concrete abuse example and affected data |
| Before | Observed behavior, or clearly labeled unverified risk |
| Change | Exact migration/function/configuration and purpose |
| Enforcement point | Database, API, storage, browser, or infrastructure |
| Evidence | Test command, release/commit, environment, date, sanitized results |
| After | Expected vs actual allowed/denied behavior and state checks |
| Deployment | Applied version and production verification status |
| Limitations | Remaining risks and assumptions |
| Operations | Alert, owner, recovery action, next review |

Example explanation: “Previously this endpoint's tenant isolation was unverified. We added/verified server-side ownership and action checks. Tenant A then requested Tenant B's invoice through both the route and direct API; neither returned its data, while Tenant B's authorized request succeeded.” Only replace this example with a completed-work claim after collecting evidence.

## 14. Reference guidance

These references support specific mechanisms, not a certification of this application:

- [Supabase API security](https://supabase.com/docs/guides/api/securing-your-api): grants, exposed schemas and API boundaries.
- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security): database enforcement and privileged bypass considerations.
- [Supabase database functions](https://supabase.com/docs/guides/database/functions): invoker/definer execution and safe function configuration.
- [Supabase sign-out](https://supabase.com/docs/guides/auth/signout): issued access tokens can remain valid until expiry.
- [Supabase shared responsibilities](https://supabase.com/docs/guides/deployment/shared-responsibility-model): application-side security and resource responsibilities.
- [Cloudflare DDoS protection](https://developers.cloudflare.com/ddos-protection/): protection for covered traffic.
- [OWASP ASVS 5.0](https://github.com/OWASP/ASVS/tree/v5.0.0/5.0): verification baseline and review mapping.
