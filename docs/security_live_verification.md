# Live security verification — read-only catalog collection

Status: Prepared, NOT executed. The current session has no usable database connection. This is documentation, not an applied migration.

Use an authorized administrative or catalog-reader session that can inspect metadata, inside a READ ONLY transaction. Do not run application RPCs or mutation tests to collect this evidence. Do not export customer rows, passwords, JWTs, secret keys, or the contents of `.temp/pooler-url`.

These queries collect catalog metadata and bucket flags, not business records. Review policy expressions privately before sharing, since definitions can contain literals. If permissions prevent a query, record the missing evidence rather than granting broader access automatically.

```sql
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '15s';
SET LOCAL lock_timeout = '2s';

-- RLS status and ownership. Views need separate security-mode review.
SELECT n.nspname AS schema_name, c.relname AS object_name,
       c.relkind, pg_get_userbyid(c.relowner) AS owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls,
       c.reloptions
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public', 'storage')
  AND c.relkind IN ('r', 'p', 'v', 'm')
ORDER BY 1, 2;

-- Policy expressions and combination mode.
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname IN ('public', 'storage')
ORDER BY schemaname, tablename, policyname;

-- Function privileges resolved through role membership/PUBLIC grants.
-- Missing runtime roles would require adapting the role-name list.
SELECT p.oid::regprocedure::text AS signature,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS user_execute,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
ORDER BY 1;

-- Effective table privileges. Column-specific grants also need review.
SELECT c.oid::regclass::text AS relation, r.role_name,
       has_table_privilege(r.role_name, c.oid, 'SELECT') AS can_select,
       has_table_privilege(r.role_name, c.oid, 'INSERT') AS can_insert,
       has_table_privilege(r.role_name, c.oid, 'UPDATE') AS can_update,
       has_table_privilege(r.role_name, c.oid, 'DELETE') AS can_delete
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(role_name)
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v')
ORDER BY 1, 2;

-- Bucket visibility only; no file rows or object URLs.
SELECT id, public FROM storage.buckets
WHERE id IN ('repair-photos', 'expense-receipts');

-- Schema migration identifiers only, not stored SQL statement bodies.
SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;

ROLLBACK;
```

If a missing metadata table aborts the transaction, roll it back and rerun other sections separately in READ ONLY transactions. Do not repair schema or create missing objects during collection.

## Additional evidence to inspect through the authorized connection

- `pg_get_functiondef` for legacy/v2 checkout, amount validation, bulk pricing, tenant/permission/branch helpers, platform-admin guard, and repair payment. Read definitions privately and redact any embedded secrets before sharing.
- Function search paths, owner/BYPASSRLS behavior, effective column privileges, relevant triggers/constraints, default privileges, and exposed API schemas. A policy existing does not prove it is restrictive enough or that no alternate endpoint exists.
- Actual applied versions compared with repository migration collisions; do not rename migrations or run a push as part of verification.
- Provider auth/session/MFA configuration, API/endpoint rate limits, and gateway bypass controls through read-only management views.
- Browser security headers and backup/alert configuration separately; catalog results cannot establish them.

## Classification record

For each SEC finding record environment, observation time, deployed definition/grant, owner, observed difference from source, and status:

- **Confirmed deployed exposure:** Relevant deployed configuration matches the vulnerable source path. Distinguish configuration proof from reproduced exploit.
- **Protected in deployment:** A verified deployed control closes that exact path; cite it and check native/web compatibility.
- **Unverified:** Access/evidence is incomplete. Missing evidence is not a passing security result.

Role-based execution and adversarial fixtures belong in an isolated test environment. This catalog collection does not create users, impersonate accounts, invoke application mutations, or validate financial behavior.
