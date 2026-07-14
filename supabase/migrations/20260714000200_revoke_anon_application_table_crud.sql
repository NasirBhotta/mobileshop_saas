-- Security Patch 2: public application tables are not used before an
-- authenticated session exists. Remove only anonymous CRUD table grants.
--
-- This migration intentionally does not change authenticated grants, RLS,
-- policies, schemas, tables, columns, functions, triggers, or sequences.
--
-- ALTER DEFAULT PRIVILEGES is intentionally omitted. The deployed exports do
-- not identify the role that creates future application tables. PostgreSQL
-- default privileges belong to that creator role, so no role is assumed here.

do $security_patch$
declare
  app_tables constant text[] := array[
    'account_transactions',
    'accounts',
    'branches',
    'business_report_delivery_jobs',
    'business_report_schedules',
    'categories',
    'customer_settlements',
    'customers',
    'discount_audit_logs',
    'expense_categories',
    'expenses',
    'goods_receipt_items',
    'goods_receipts',
    'held_carts',
    'inventory',
    'inventory_units',
    'products',
    'purchase_order_items',
    'purchase_orders',
    'receipt_delivery_logs',
    'recurring_expense_rules',
    'repair_status_logs',
    'repair_tickets',
    'sale_items',
    'sale_payments',
    'sale_return_items',
    'sale_returns',
    'sales',
    'sales_report_delivery_jobs',
    'sales_report_schedules',
    'stock_adjustments',
    'supplier_payments',
    'supplier_products',
    'suppliers',
    'tenant_addons',
    'tenant_settings',
    'tenants',
    'users',
    'void_logs'
  ];
  table_name text;
  qualified_table text;
  privilege_name text;
  existing_tables text[];
  rls_before jsonb;
  rls_after jsonb;
  policies_before jsonb;
  policies_after jsonb;
begin
  select coalesce(array_agg(t.table_name order by t.table_name), array[]::text[])
  into existing_tables
  from unnest(app_tables) as t(table_name)
  where to_regclass(format('public.%I', t.table_name)) is not null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table_name', c.relname,
        'rls_enabled', c.relrowsecurity,
        'force_rls', c.relforcerowsecurity
      ) order by c.relname
    ),
    '[]'::jsonb
  )
  into rls_before
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = any(existing_tables);

  select coalesce(
    jsonb_agg(to_jsonb(p) order by p.tablename, p.policyname),
    '[]'::jsonb
  )
  into policies_before
  from pg_catalog.pg_policies p
  where p.schemaname = 'public'
    and p.tablename = any(existing_tables);

  foreach table_name in array app_tables loop
    qualified_table := format('public.%I', table_name);

    -- Keep the migration compatible with environments where a later module
    -- has not yet been installed, while never touching an unrelated table.
    if to_regclass(qualified_table) is null then
      raise notice 'Security Patch 2 skipped missing table %', qualified_table;
      continue;
    end if;

    execute format(
      'revoke select, insert, update, delete on table %I.%I from anon',
      'public',
      table_name
    );

    foreach privilege_name in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if has_table_privilege('anon', qualified_table, privilege_name) then
        raise exception
          'Security Patch 2 verification failed: anon still has % on %',
          privilege_name,
          qualified_table;
      end if;

      if not has_table_privilege('authenticated', qualified_table, privilege_name) then
        raise exception
          'Security Patch 2 verification failed: authenticated lost % on %',
          privilege_name,
          qualified_table;
      end if;
    end loop;
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'table_name', c.relname,
        'rls_enabled', c.relrowsecurity,
        'force_rls', c.relforcerowsecurity
      ) order by c.relname
    ),
    '[]'::jsonb
  )
  into rls_after
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = any(existing_tables);

  select coalesce(
    jsonb_agg(to_jsonb(p) order by p.tablename, p.policyname),
    '[]'::jsonb
  )
  into policies_after
  from pg_catalog.pg_policies p
  where p.schemaname = 'public'
    and p.tablename = any(existing_tables);

  if rls_before is distinct from rls_after then
    raise exception 'Security Patch 2 verification failed: RLS state changed';
  end if;

  if policies_before is distinct from policies_after then
    raise exception 'Security Patch 2 verification failed: policies changed';
  end if;
end
$security_patch$;

-- Exact rollback for every existing table in the allow-list:
-- grant select, insert, update, delete on table <the existing allow-listed
-- public tables> to anon;
