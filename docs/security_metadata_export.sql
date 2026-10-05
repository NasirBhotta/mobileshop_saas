-- Manual read-only audit export. NOT a migration. NOT executed by this agent.
-- Run in the intended Supabase project's SQL Editor using authorized access.
-- Returns one JSON result; reads catalogs and bucket flags, not customer rows.
-- Review definitions/policy literals before sharing; redact embedded secrets.
-- No application functions are invoked. No privileges or schema are changed.

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '20s';
SET LOCAL lock_timeout = '2s';

WITH runtime_roles AS (
  SELECT oid, rolname FROM pg_roles
  WHERE rolname IN ('anon', 'authenticated', 'service_role')
), relations AS (
  SELECT c.oid, n.nspname AS schema_name, c.relname AS object_name,
         c.relkind, c.relowner, c.relrowsecurity, c.relforcerowsecurity,
         c.reloptions
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('public', 'storage')
    AND c.relkind IN ('r', 'p', 'v', 'm')
), functions AS (
  SELECT p.* FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f'
), selected_functions AS (
  SELECT * FROM functions
  WHERE proname IN (
    'commit_pos_sale', 'commit_pos_sale_v2',
    'commit_pos_sale_v2_unvalidated', 'validate_pos_sale_amounts',
    'current_user_tenant_id', 'current_user_has_permission',
    'current_user_can_access_branch', 'current_user_has_branch_permission',
    'require_role_manager_tenant', 'require_active_platform_admin',
    'bulk_update_product_prices', 'product_has_active_imei_units',
    'verify_pos_discount_approval', 'record_repair_payment_v2',
    'protect_user_client_fields', 'set_user_branch_role'
  )
)
SELECT jsonb_build_object(
  'collected_at_utc', to_char(clock_timestamp() AT TIME ZONE 'UTC',
                             'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'transaction_read_only', current_setting('transaction_read_only'),
  'database_version', current_setting('server_version'),
  'runtime_roles', (SELECT jsonb_agg(rolname ORDER BY rolname) FROM runtime_roles),
  'relations', (
    SELECT jsonb_agg(jsonb_build_object(
      'schema', schema_name, 'name', object_name, 'kind', relkind,
      'owner', pg_get_userbyid(relowner), 'rls_enabled', relrowsecurity,
      'force_rls', relforcerowsecurity, 'options', reloptions
    ) ORDER BY schema_name, object_name) FROM relations
  ),
  'policies', (
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.schemaname, x.tablename, x.policyname)
    FROM (
      SELECT schemaname, tablename, policyname, permissive, roles, cmd,
             qual, with_check
      FROM pg_policies WHERE schemaname IN ('public', 'storage')
    ) x
  ),
  'table_privileges', (
    SELECT jsonb_agg(jsonb_build_object(
      'schema', t.schema_name, 'table', t.object_name, 'role', r.rolname,
      'select', has_table_privilege(r.oid, t.oid, 'SELECT'),
      'insert', has_table_privilege(r.oid, t.oid, 'INSERT'),
      'update', has_table_privilege(r.oid, t.oid, 'UPDATE'),
      'delete', has_table_privilege(r.oid, t.oid, 'DELETE')
    ) ORDER BY t.schema_name, t.object_name, r.rolname)
    FROM relations t CROSS JOIN runtime_roles r
  ),
  'explicit_column_grants', (
    SELECT jsonb_agg(jsonb_build_object(
      'schema', t.schema_name, 'table', t.object_name,
      'column', a.attname, 'acl', a.attacl
    ) ORDER BY t.schema_name, t.object_name, a.attnum)
    FROM relations t JOIN pg_attribute a ON a.attrelid = t.oid
    WHERE a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
  ),
  'function_access', (
    SELECT jsonb_agg(jsonb_build_object(
      'signature', f.oid::regprocedure::text,
      'owner', owner_role.rolname,
      'owner_superuser', owner_role.rolsuper,
      'owner_bypass_rls', owner_role.rolbypassrls,
      'security_definer', f.prosecdef,
      'role', r.rolname,
      'execute', has_function_privilege(r.oid, f.oid, 'EXECUTE')
    ) ORDER BY f.oid::regprocedure::text, r.rolname)
    FROM functions f
    JOIN pg_roles owner_role ON owner_role.oid = f.proowner
    CROSS JOIN runtime_roles r
  ),
  'selected_function_definitions', (
    SELECT jsonb_agg(jsonb_build_object(
      'signature', oid::regprocedure::text,
      'definition', pg_get_functiondef(oid)
    ) ORDER BY oid::regprocedure::text) FROM selected_functions
  ),
  'constraints', (
    SELECT jsonb_agg(jsonb_build_object(
      'schema', t.schema_name, 'table', t.object_name,
      'name', con.conname, 'definition', pg_get_constraintdef(con.oid),
      'validated', con.convalidated
    ) ORDER BY t.schema_name, t.object_name, con.conname)
    FROM relations t JOIN pg_constraint con ON con.conrelid = t.oid
    WHERE t.schema_name = 'public'
  ),
  'triggers', (
    SELECT jsonb_agg(jsonb_build_object(
      'schema', t.schema_name, 'table', t.object_name,
      'name', tr.tgname, 'enabled', tr.tgenabled,
      'definition', pg_get_triggerdef(tr.oid)
    ) ORDER BY t.schema_name, t.object_name, tr.tgname)
    FROM relations t JOIN pg_trigger tr ON tr.tgrelid = t.oid
    WHERE NOT tr.tgisinternal
  ),
  'bucket_flags', (
    SELECT jsonb_agg(jsonb_build_object('id', id, 'public', public) ORDER BY id)
    FROM storage.buckets WHERE id IN ('repair-photos', 'expense-receipts')
  ),
  'migration_history_available',
    to_regclass('supabase_migrations.schema_migrations') IS NOT NULL
) AS security_metadata_export;

COMMIT; -- Read-only transaction; no persistent changes were made.

-- Optional SECOND run, only if migration_history_available is true:
-- BEGIN TRANSACTION READ ONLY;
-- SET LOCAL statement_timeout = '10s';
-- SELECT jsonb_agg(version ORDER BY version) AS applied_migration_versions
-- FROM supabase_migrations.schema_migrations;
-- COMMIT;
