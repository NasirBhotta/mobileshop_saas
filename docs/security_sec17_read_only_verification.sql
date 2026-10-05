-- SEC-17 read-only verification for Supabase SQL Editor.
-- Safe to run: every statement is SELECT/CTE only. No data or schema is changed.
-- Copy all output and share it as a text file; redact only secrets if any appear.

-- 1. Relevant public tables, RLS state and replica status.
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  case when pub.relid is null then false else true end as in_realtime_publication
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_publication_tables pub
  on pub.pubname = 'supabase_realtime'
 and pub.schemaname = n.nspname
 and pub.tablename = c.relname
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and c.relname in (
    'sales', 'sale_items', 'sale_payments',
    'products', 'inventory', 'stock_adjustments',
    'sale_returns', 'sale_return_items',
    'inventory_units', 'customer_purchases',
    'users', 'branches', 'user_branch_role_assignments',
    'roles', 'permissions', 'role_permissions'
  )
order by c.relname;

-- 2. Exact column contracts and defaults for the affected tables.
select
  table_name,
  ordinal_position,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default,
  is_identity,
  is_generated
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'sales', 'sale_items', 'sale_payments',
    'products', 'inventory', 'stock_adjustments',
    'sale_returns', 'sale_return_items',
    'inventory_units', 'customer_purchases'
  )
order by table_name, ordinal_position;

-- 3. Constraints, including foreign keys and checks that secure RPCs must preserve.
select
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  pg_get_constraintdef(con.oid, true) as definition
from information_schema.table_constraints tc
join pg_namespace ns on ns.nspname = tc.table_schema
join pg_class cls on cls.relname = tc.table_name and cls.relnamespace = ns.oid
join pg_constraint con on con.conrelid = cls.oid and con.conname = tc.constraint_name
where tc.table_schema = 'public'
  and tc.table_name in (
    'sales', 'sale_items', 'sale_payments',
    'products', 'inventory', 'stock_adjustments',
    'sale_returns', 'sale_return_items',
    'inventory_units', 'customer_purchases'
  )
order by tc.table_name, tc.constraint_type, tc.constraint_name;

-- 4. Every effective RLS policy for affected tables.
select
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual as using_expression,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'sales', 'sale_items', 'sale_payments',
    'products', 'inventory', 'stock_adjustments',
    'sale_returns', 'sale_return_items',
    'inventory_units', 'customer_purchases'
  )
order by tablename, policyname;

-- 5. Table privileges for anon/authenticated/service_role/PUBLIC.
select
  table_name,
  grantee,
  privilege_type,
  is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'sales', 'sale_items', 'sale_payments',
    'products', 'inventory', 'stock_adjustments',
    'sale_returns', 'sale_return_items',
    'inventory_units', 'customer_purchases'
  )
  and grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')
order by table_name, grantee, privilege_type;

-- 6. Triggers and their full functions: these can enforce or affect invariants.
select
  c.relname as table_name,
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid, true) as trigger_definition,
  pn.nspname as function_schema,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as function_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
join pg_namespace pn on pn.oid = p.pronamespace
where n.nspname = 'public'
  and not t.tgisinternal
  and c.relname in (
    'sales', 'sale_items', 'sale_payments',
    'products', 'inventory', 'stock_adjustments',
    'sale_returns', 'sale_return_items',
    'inventory_units', 'customer_purchases'
  )
order by c.relname, t.tgname;

-- 7. Relevant RPCs and authorization helpers, including source and execute grants.
with relevant_functions as (
  select p.oid, n.nspname as schema_name, p.proname,
    pg_get_function_identity_arguments(p.oid) as identity_arguments,
    pg_get_function_result(p.oid) as result_type,
    p.prosecdef as security_definer,
    p.proconfig as config,
    pg_get_functiondef(p.oid) as definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'commit_pos_sale_v2', 'commit_pos_sale_v2_unvalidated', 'commit_pos_sale',
      'post_pos_return_refund', 'post_pos_credit_return',
      'current_user_tenant_id', 'current_user_has_permission',
      'current_user_has_branch_permission', 'current_user_can_access_branch'
    )
)
select
  rf.schema_name,
  rf.proname,
  rf.identity_arguments,
  rf.result_type,
  rf.security_definer,
  rf.config,
  coalesce(array_agg(distinct acl.grantee order by acl.grantee)
    filter (where acl.privilege_type = 'EXECUTE'), '{}'::text[]) as execute_grantees,
  rf.definition
from relevant_functions rf
left join lateral aclexplode(coalesce(proacl, acldefault('f', proowner))) acl_raw on true
left join lateral (
  select case when acl_raw.grantee = 0 then 'PUBLIC' else pg_get_userbyid(acl_raw.grantee) end as grantee,
         acl_raw.privilege_type
) acl on true
join pg_proc p on p.oid = rf.oid
group by rf.oid, rf.schema_name, rf.proname, rf.identity_arguments,
  rf.result_type, rf.security_definer, rf.config, rf.definition
order by rf.proname, rf.identity_arguments;

-- 8. Current permission catalog values required to map role/action checks.
select
  p.key as permission_key,
  r.name as role_name,
  rp.created_at as assigned_at
from public.permissions p
left join public.role_permissions rp on rp.permission_id = p.id
left join public.roles r on r.id = rp.role_id
where p.key in (
  'pos.sale.create', 'pos.sale.return', 'pos.sale.return.approve',
  'inventory.product.create', 'inventory.product.edit', 'inventory.product.delete',
  'inventory.price.edit', 'inventory.stock.adjust', 'inventory.stock.adjustments'
)
order by p.key, r.name;
