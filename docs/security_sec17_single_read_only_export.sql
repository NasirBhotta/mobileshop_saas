-- SEC-17 single-result read-only export for Supabase SQL Editor.
-- Run this file instead of the multi-query version. It returns one JSON object.
-- It only reads PostgreSQL/Supabase metadata. No data or schema is changed.
with
tables as (
  select c.relname as table_name, c.relrowsecurity as rls_enabled,
    c.relforcerowsecurity as rls_forced,
    (pub.tablename is not null) as in_realtime_publication
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_publication_tables pub on pub.pubname = 'supabase_realtime'
    and pub.schemaname = n.nspname and pub.tablename = c.relname
  where n.nspname = 'public' and c.relkind in ('r', 'p')
    and c.relname = any(array[
      'sales','sale_items','sale_payments','products','inventory','stock_adjustments',
      'sale_returns','sale_return_items','inventory_units','customer_purchases',
      'users','branches','user_branch_role_assignments','roles','permissions','role_permissions'
    ])
),
columns_export as (
  select table_name, ordinal_position, column_name, data_type, udt_name,
    is_nullable, column_default, is_identity, is_generated
  from information_schema.columns
  where table_schema = 'public' and table_name = any(array[
    'sales','sale_items','sale_payments','products','inventory','stock_adjustments',
    'sale_returns','sale_return_items','inventory_units','customer_purchases'
  ])
),
constraints_export as (
  select tc.table_name, tc.constraint_name, tc.constraint_type,
    pg_get_constraintdef(con.oid, true) as definition
  from information_schema.table_constraints tc
  join pg_namespace ns on ns.nspname = tc.table_schema
  join pg_class cls on cls.relname = tc.table_name and cls.relnamespace = ns.oid
  join pg_constraint con on con.conrelid = cls.oid and con.conname = tc.constraint_name
  where tc.table_schema = 'public' and tc.table_name = any(array[
    'sales','sale_items','sale_payments','products','inventory','stock_adjustments',
    'sale_returns','sale_return_items','inventory_units','customer_purchases'
  ])
),
policies as (
  select tablename, policyname, permissive, roles, cmd,
    qual as using_expression, with_check
  from pg_policies
  where schemaname = 'public' and tablename = any(array[
    'sales','sale_items','sale_payments','products','inventory','stock_adjustments',
    'sale_returns','sale_return_items','inventory_units','customer_purchases'
  ])
),
table_grants as (
  select table_name, grantee, privilege_type, is_grantable
  from information_schema.role_table_grants
  where table_schema = 'public' and table_name = any(array[
    'sales','sale_items','sale_payments','products','inventory','stock_adjustments',
    'sale_returns','sale_return_items','inventory_units','customer_purchases'
  ]) and grantee = any(array['anon','authenticated','service_role','PUBLIC'])
),
triggers as (
  select c.relname as table_name, t.tgname as trigger_name,
    pg_get_triggerdef(t.oid, true) as trigger_definition,
    pn.nspname as function_schema, p.proname as function_name,
    pg_get_functiondef(p.oid) as function_definition
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
  join pg_namespace pn on pn.oid = p.pronamespace
  where n.nspname = 'public' and not t.tgisinternal and c.relname = any(array[
    'sales','sale_items','sale_payments','products','inventory','stock_adjustments',
    'sale_returns','sale_return_items','inventory_units','customer_purchases'
  ])
),
functions_export as (
  select p.oid, n.nspname as schema_name, p.proname,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    p.prosecdef as security_definer, p.proconfig as config,
    coalesce(array_agg(distinct case when acl.grantee = 0 then 'PUBLIC'
      else pg_get_userbyid(acl.grantee) end order by case when acl.grantee = 0
      then 'PUBLIC' else pg_get_userbyid(acl.grantee) end)
      filter (where acl.privilege_type = 'EXECUTE'), '{}'::text[]) as execute_grantees,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  left join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl on true
  where n.nspname = 'public' and p.proname = any(array[
    'commit_pos_sale_v2','commit_pos_sale_v2_unvalidated','commit_pos_sale',
    'post_pos_return_refund','post_pos_credit_return','current_user_tenant_id',
    'current_user_has_permission','current_user_has_branch_permission',
    'current_user_can_access_branch'
  ])
  group by p.oid, n.nspname, p.proname
),
permission_matrix as (
  select distinct p.key as permission_key, r.code as role_code, r.name as role_name
  from public.permissions p
  left join public.role_permissions rp on rp.permission_id = p.id
  left join public.roles r on r.id = rp.role_id
  where p.key = any(array[
    'pos.sale.create','pos.sale.return','pos.sale.return.approve',
    'inventory.product.create','inventory.product.update','inventory.product.delete',
    'inventory.stock.adjust'
  ])
)
select jsonb_build_object(
  'exported_at', now(),
  'tables', coalesce((select jsonb_agg(to_jsonb(x) order by x.table_name) from tables x), '[]'::jsonb),
  'columns', coalesce((select jsonb_agg(to_jsonb(x) order by x.table_name, x.ordinal_position) from columns_export x), '[]'::jsonb),
  'constraints', coalesce((select jsonb_agg(to_jsonb(x) order by x.table_name, x.constraint_name) from constraints_export x), '[]'::jsonb),
  'policies', coalesce((select jsonb_agg(to_jsonb(x) order by x.tablename, x.policyname) from policies x), '[]'::jsonb),
  'table_grants', coalesce((select jsonb_agg(to_jsonb(x) order by x.table_name, x.grantee, x.privilege_type) from table_grants x), '[]'::jsonb),
  'triggers', coalesce((select jsonb_agg(to_jsonb(x) order by x.table_name, x.trigger_name) from triggers x), '[]'::jsonb),
  'functions', coalesce((select jsonb_agg(to_jsonb(x) order by x.proname, x.identity_arguments) from functions_export x), '[]'::jsonb),
  'permission_matrix', coalesce((select jsonb_agg(to_jsonb(x) order by x.permission_key, x.role_code) from permission_matrix x), '[]'::jsonb)
) as security_metadata_export;
