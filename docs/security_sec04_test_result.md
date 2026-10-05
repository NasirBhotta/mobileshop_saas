# SEC-04: selected-branch revocation test result

Date: 2026-10-05. Status: isolated candidate tested, NOT deployed.

**26 checks passed.** The exported helper allowed revoked staff to read synthetic supplier data through the exported RLS predicate because the branch remained selected. The candidate requires a current active branch role for configured staff; the same access was then denied.

Valid owner/selected-staff operations and intentionally supported never-configured legacy staff were preserved. The candidate does not expand access to assigned but unselected branches. Revoked/deleted roles, disabled users, foreign tenants, missing identities and NULL scope were covered. Function owner/ACL were preserved in the fixture.

Artifacts outside application source:

- [Candidate SQL](../../security-review-null-tenant/sec04/candidate.sql)
- [Exact diff](../../security-review-null-tenant/sec04/candidate.diff)
- [Test results](../../security-review-null-tenant/sec04/results.json)
- [Reproduction and limitations](../../security-review-null-tenant/sec04/README.md)

Limits: embedded PostgreSQL, minimal synthetic schema and auth shim; no real mobile/desktop integration or live Supabase test. Legacy fallback relies on retaining historical revoked assignments. Action-level policies and other audit findings are not fixed by this change.

Existing application code, migrations and live database remain unchanged. This candidate, SEC-03 and SEC-16 are local artifacts, not deployed protection. Before deployment, review shared helper callers and test real branch switching/role-management/offline-sync flows in staging.
