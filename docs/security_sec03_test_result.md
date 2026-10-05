# SEC-03: disabled-account isolated regression result

Date: 2026-10-05. Status: candidate tested in isolation, NOT deployed.

The exported tenant and global permission helpers were reproduced in an in-memory PostgreSQL environment. A disabled user's profile was hidden by users RLS, but the privileged helpers still returned a tenant/permission, allowed a synthetic procurement read, and passed the nested role-manager guard.

The proposed correction adds active/non-deleted actor checks to both helpers. **24 checks passed**: before/after behavior, denied reads and mutations, active-user access, nested role-manager denial, role/permission revocation, preserved owner/ACL, and unchanged foreign records.

The previous SEC-16 suite was also run with both candidates applied: **25 combined checks passed**. This is regression coverage, not 25 additional distinct features.

Artifacts outside the app repository:

- [Candidate SQL](../../security-review-null-tenant/sec03/candidate.sql)
- [Exact diff](../../security-review-null-tenant/sec03/candidate.diff)
- [Results](../../security-review-null-tenant/sec03/results.json)
- [Scope and reproduction](../../security-review-null-tenant/sec03/README.md)
- [Combined results](../../security-review-null-tenant/combined-results.json)

No real JWT sessions, full client flows, production data, or complete Supabase environment were exercised. Other privileged functions and broader table/action policy gaps remain open. The tested change does not remove already downloaded offline records or make public media private.

Existing application files/migrations and live Supabase are unchanged. The next independent priority is selected-branch access after branch-role revocation (SEC-04); production release still requires staging compatibility checks and explicit authorization.
