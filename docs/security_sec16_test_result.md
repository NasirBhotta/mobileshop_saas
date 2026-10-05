# SEC-16: isolated test result

Date: 2026-10-05. Status: candidate fix tested in isolation, not deployed.

The NULL-tenant branch-permission defect was reproduced in an in-memory PostgreSQL engine using the user-exported function, selected dependencies and accounts RLS policies. A synthetic active onboarding owner could read accounts across two synthetic tenants as the `authenticated` role. No production data or identity was used.

The candidate changes only the initial guard: reject missing actor/tenant/branch, compare tenants with `IS DISTINCT FROM`, and require account activity to be true. **25 checks passed**, including baseline reproduction, denied access after the change, valid owner/staff access, revoked/disabled cases, onboarding insertion, and preserved function ownership/grants.

Artifacts are outside the application repository:

- [Review notes](../../security-review-null-tenant/README.md)
- [Candidate SQL — not deployed](../../security-review-null-tenant/candidate.sql)
- [Exact function diff](../../security-review-null-tenant/candidate.diff)
- [Executable regression harness](../../security-review-null-tenant/test.mjs)
- [Recorded results](../../security-review-null-tenant/results.json)

Limitations: minimal synthetic schema, fixture auth.uid, embedded PostgreSQL rather than a complete Supabase environment; no native/web app, real auth/API, concurrency or live deployment tests. Normal signup insertion was tested, not the full onboarding UI or RPC workflow. Other audit findings are unresolved.

Application source, migrations and live database were not changed. The next release gate is supported-client/staging verification and explicit deployment approval; local tests are not permission to deploy.
