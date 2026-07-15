-- Package Patch 2: editable commercial package presets.
-- This catalog is not enforced and does not modify public.tenants.plan.

create or replace function public.sync_package_presets()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  insert into public.plans (key, name, description, is_active)
  values
    ('starter', 'Starter', 'Starter package preset.', true),
    ('business', 'Business', 'Business package preset.', true),
    ('enterprise', 'Enterprise', 'Enterprise package preset.', true)
  on conflict do nothing;

  insert into public.features (key, module, name, description, is_active)
  values
    ('dashboard.access', 'dashboard', 'Dashboard',
     'Access the implemented dashboard module.', true),
    ('branches.access', 'branches', 'Branches',
     'Access tenant branches and branch selection.', true),
    ('users.access', 'users', 'Users and roles',
     'Access implemented user and role-management features.', true),
    ('inventory.access', 'inventory', 'Inventory',
     'Access products, categories, stock, IMEI and barcode features.', true),
    ('pos.access', 'pos', 'Point of sale',
     'Access point-of-sale and returns.', true),
    ('customers.access', 'customers', 'Customers',
     'Access customers, credit and settlements.', true),
    ('repairs.access', 'repairs', 'Repairs',
     'Access repair intake, workflow and payments.', true),
    ('suppliers.access', 'suppliers', 'Suppliers',
     'Access supplier records and payments.', true),
    ('purchases.access', 'purchases', 'Purchases',
     'Access purchase orders and goods receiving.', true),
    ('expenses.access', 'expenses', 'Expenses',
     'Access expenses, categories and recurring rules.', true),
    ('accounts.access', 'accounts', 'Accounts',
     'Access financial accounts and transactions.', true),
    ('reports.access', 'reports', 'Reports',
     'Access implemented sales and business reports.', true),
    ('settings.access', 'settings', 'Settings',
     'Access implemented shop, branch and role settings.', true),
    ('receipts.access', 'receipts', 'Receipts',
     'Access receipt viewing, printing and sending.', true),
    ('purchases.procurement', 'purchases', 'Procurement',
     'Access suppliers, purchase orders and goods receiving.', true),
    ('inventory.csv_import', 'inventory', 'CSV product import',
     'Import inventory products from CSV.', true),
    ('inventory.bulk_pricing', 'inventory', 'Bulk pricing',
     'Update product prices in bulk.', true),
    ('reports.export', 'reports', 'Report export',
     'Export sales and business reports.', true),
    ('reports.scheduling', 'reports', 'Scheduled reports',
     'Create and manage scheduled report delivery.', true),
    ('expenses.history', 'expenses', 'Expense history',
     'View expense history within the package history limit.', true)
  on conflict do nothing;

  -- All implemented modules remain represented as available on every preset.
  insert into public.plan_features (plan_id, feature_id, enabled, reason)
  select p.id, f.id, true, 'Package Patch 2 current runtime default'
  from public.plans p
  cross join public.features f
  where p.key in ('starter', 'business', 'enterprise')
    and f.key in (
      'dashboard.access', 'branches.access', 'users.access',
      'inventory.access', 'pos.access', 'customers.access',
      'repairs.access', 'suppliers.access', 'purchases.access',
      'expenses.access', 'accounts.access', 'reports.access',
      'settings.access', 'receipts.access', 'purchases.procurement',
      'inventory.csv_import', 'inventory.bulk_pricing', 'expenses.history'
    )
  on conflict (plan_id, feature_id) do nothing;

  -- Export and scheduling are commercial defaults for Business/Enterprise.
  -- Disabled Starter rows are explicit defaults, not runtime enforcement.
  insert into public.plan_features (plan_id, feature_id, enabled, reason)
  select p.id, f.id, p.key in ('business', 'enterprise'),
         'Package Patch 2 report default'
  from public.plans p
  cross join public.features f
  where p.key in ('starter', 'business', 'enterprise')
    and f.key in ('reports.export', 'reports.scheduling')
  on conflict (plan_id, feature_id) do nothing;

  -- -1 is the stable sentinel for an unlimited numeric package limit.
  insert into public.plan_limits (plan_id, key, value, reason)
  select p.id, 'expenses.history_days',
         case p.key
           when 'starter' then 30
           when 'business' then 365
           when 'enterprise' then -1
         end,
         'Package Patch 2 current expense-history default'
  from public.plans p
  where p.key in ('starter', 'business', 'enterprise')
  on conflict (plan_id, key) do nothing;
end
$function$;

revoke all on function public.sync_package_presets() from public;
revoke all on function public.sync_package_presets() from anon;
revoke all on function public.sync_package_presets() from authenticated;

select public.sync_package_presets();
