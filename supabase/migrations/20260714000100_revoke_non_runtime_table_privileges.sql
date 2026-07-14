-- Security Patch 1: remove table privileges that the application runtime does
-- not require. This migration intentionally does not change CRUD grants, RLS,
-- policies, table definitions, functions, or triggers.
--
-- ALTER DEFAULT PRIVILEGES is intentionally omitted. The deployed exports used
-- for this patch do not identify the table owners or the role that will create
-- future tables. Default privileges are owned by the creating role, so applying
-- them for an assumed role would not reliably protect future tables.

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
  runtime_role text;
  removed_privilege text;
  retained_privilege text;
begin
  foreach table_name in array app_tables loop
    qualified_table := format('public.%I', table_name);

    -- Keep the migration usable in environments where a later application
    -- module has not been installed yet. Only confirmed tables that exist are
    -- changed; no unrelated public-schema table is included.
    if to_regclass(qualified_table) is null then
      raise notice 'Security Patch 1 skipped missing table %', qualified_table;
      continue;
    end if;

    execute format(
      'revoke truncate, references, trigger on table %I.%I from anon, authenticated',
      'public',
      table_name
    );

    -- Postcondition: neither API runtime role retains a removed privilege.
    foreach runtime_role in array array['anon', 'authenticated'] loop
      foreach removed_privilege in array array['TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
        if has_table_privilege(runtime_role, qualified_table, removed_privilege) then
          raise exception
            'Security Patch 1 verification failed: role % still has % on %',
            runtime_role,
            removed_privilege,
            qualified_table;
        end if;
      end loop;
    end loop;

    -- The deployed grant baseline gives authenticated all four CRUD grants on
    -- every confirmed application table. Fail atomically if this patch ever
    -- removes or runs against a baseline missing one of those grants.
    foreach retained_privilege in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if not has_table_privilege('authenticated', qualified_table, retained_privilege) then
        raise exception
          'Security Patch 1 verification failed: authenticated lacks retained privilege % on %',
          retained_privilege,
          qualified_table;
      end if;
    end loop;
  end loop;
end
$security_patch$;

-- Verification queries for deployment review (read-only):
--
-- 1. Removed privileges must return zero rows for the allow-listed tables:
-- select table_name, grantee, privilege_type
-- from information_schema.role_table_grants
-- where table_schema = 'public'
--   and grantee in ('anon', 'authenticated')
--   and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')
--   and table_name = any (array[...the app_tables allow-list above...]);
--
-- 2. Authenticated CRUD grants remain visible in role_table_grants. RLS and
-- pg_policies are not modified by any statement in this migration.
--
-- Exact rollback responsibility:
-- grant truncate, references, trigger on table <each existing allow-listed
-- public table> to anon, authenticated;
