-- Supplemental metadata only. Not a migration; not executed by this agent.
-- Reads no account/customer rows and calls no application functions.
-- Review function text for embedded secrets before sharing.
-- Missing migration-history tables are supported; no version rows are queried.
-- If a prior attempt left this editor session in an aborted transaction,
-- run ROLLBACK separately before running this file.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '15s';
SET LOCAL lock_timeout = '2s';
SELECT jsonb_build_object(
  'users_column_metadata', (
    SELECT jsonb_agg(jsonb_build_object(
      'name', a.attname, 'not_null', a.attnotnull,
      'type', format_type(a.atttypid, a.atttypmod)
    ) ORDER BY a.attnum)
    FROM pg_attribute a
    WHERE a.attrelid = 'public.users'::regclass AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.attname IN ('id','tenant_id','branch_id','role','is_active','deleted_at')
  ),
  'supporting_functions', (
    SELECT jsonb_agg(jsonb_build_object(
      'signature', p.oid::regprocedure::text,
      'definition', pg_get_functiondef(p.oid)
    ) ORDER BY p.oid::regprocedure::text)
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname IN (
        'protect_user_client_insert', 'ensure_compatibility_user_role',
        'enforce_user_branch_assignment_on_selection',
        'cleanup_revoked_branch_role_overrides', 'block_direct_tenant_detach'
      )
  ),
  'migration_history_available',
    to_regclass('supabase_migrations.schema_migrations') IS NOT NULL,
  'applied_versions', NULL::jsonb,
  'applied_versions_status', 'Not collected; migration history is optional for these checks'
) AS security_metadata_followup;
COMMIT;
