-- STAGING-ONLY, READ-ONLY export for the atomic POS-return implementation.
-- This does not alter data, functions, policies, grants, or schema.
-- Run the full file in the STAGING SQL Editor and paste the one JSON result.

with target_tables(table_name) as (
  values
    ('sales'), ('sale_items'), ('sale_payments'),
    ('sale_returns'), ('sale_return_items'), ('sale_return_refund_legs'),
    ('sale_return_credit_adjustments'), ('products'), ('inventory'),
    ('accounts'), ('account_transactions'), ('customers')
),
target_functions(function_name) as (
  values
    ('post_pos_return_refund'), ('post_pos_credit_return'),
    ('commit_pos_return_v2'), ('current_user_has_branch_permission'),
    ('record_account_transaction_v2')
),
tables as (
  select c.relname as table_name, c.relrowsecurity as rls_enabled,
    c.relforcerowsecurity as rls_forced
  from target_tables wanted
  left join pg_class c on c.relname = wanted.table_name
  left join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  where n.nspname = 'public' or c.oid is null
),
columns as (
  select cols.table_name, cols.ordinal_position, cols.column_name,
    cols.data_type, cols.udt_name, cols.is_nullable, cols.column_default
  from information_schema.columns cols
  join target_tables wanted on wanted.table_name = cols.table_name
  where cols.table_schema = 'public'
),
constraints as (
  select tc.table_name, tc.constraint_name, tc.constraint_type,
    pg_get_constraintdef(con.oid, true) as definition
  from information_schema.table_constraints tc
  join target_tables wanted on wanted.table_name = tc.table_name
  join pg_namespace ns on ns.nspname = tc.table_schema
  join pg_class cls on cls.relname = tc.table_name and cls.relnamespace = ns.oid
  join pg_constraint con on con.conrelid = cls.oid and con.conname = tc.constraint_name
  where tc.table_schema = 'public'
),
policies as (
  select p.tablename, p.policyname, p.permissive, p.roles, p.cmd,
    p.qual as using_expression, p.with_check
  from pg_policies p
  join target_tables wanted on wanted.table_name = p.tablename
  where p.schemaname = 'public'
),
functions as (
  select n.nspname as schema_name, p.proname,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    p.prosecdef as security_definer, p.proconfig as config,
    coalesce(array_agg(distinct case when acl.grantee = 0 then 'PUBLIC'
      else pg_get_userbyid(acl.grantee) end order by case when acl.grantee = 0 then 'PUBLIC'
      else pg_get_userbyid(acl.grantee) end) filter (where acl.privilege_type = 'EXECUTE'),
      '{}'::text[]) as execute_grantees,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
  join target_functions wanted on wanted.function_name = p.proname
  left join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl on true
  group by p.oid, n.nspname, p.proname
),
permission_catalog as (
  select p.key, p.is_active,
    coalesce(array_agg(distinct r.code order by r.code) filter (where rp.role_id is not null),
      '{}'::text[]) as assigned_role_codes
  from public.permissions p
  left join public.role_permissions rp on rp.permission_id = p.id
  left join public.roles r on r.id = rp.role_id
  where p.key in ('pos.sale.create', 'pos.sale.return', 'pos.sale.return.approve')
  group by p.id, p.key, p.is_active
)
select jsonb_build_object(
  'tables', coalesce((select jsonb_agg(to_jsonb(t) order by t.table_name) from tables t), '[]'::jsonb),
  'columns', coalesce((select jsonb_agg(to_jsonb(c) order by c.table_name, c.ordinal_position) from columns c), '[]'::jsonb),
  'constraints', coalesce((select jsonb_agg(to_jsonb(c) order by c.table_name, c.constraint_name) from constraints c), '[]'::jsonb),
  'policies', coalesce((select jsonb_agg(to_jsonb(p) order by p.tablename, p.policyname) from policies p), '[]'::jsonb),
  'functions', coalesce((select jsonb_agg(to_jsonb(f) order by f.proname, f.identity_arguments) from functions f), '[]'::jsonb),
  'permissions', coalesce((select jsonb_agg(to_jsonb(pc) order by pc.key) from permission_catalog pc), '[]'::jsonb)
) as security_staging_return_atomic_preflight;
