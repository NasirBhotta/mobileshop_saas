-- Roles Patch 3: global permission catalog only.
-- No permission is assigned to a role and existing runtime checks are untouched.

alter table public.permissions
add column if not exists name text;

alter table public.permissions
add column if not exists is_active boolean not null default true;

update public.permissions
set name = key
where name is null or length(trim(name)) = 0;

alter table public.permissions
alter column name set not null;

alter table public.permissions
drop constraint if exists permissions_name_nonempty_check;

alter table public.permissions
add constraint permissions_name_nonempty_check
check (length(trim(name)) > 0);

create or replace function public.sync_global_permission_catalog()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  insert into public.permissions (
    key, module, action, name, description, is_active
  )
  values
    ('dashboard.overview.view', 'dashboard', 'view',
     'View dashboard', 'View dashboard summaries and operational metrics.', true),

    ('branch.location.view', 'branches', 'view',
     'View branches', 'View branches belonging to the current tenant.', true),
    ('branch.location.create', 'branches', 'create',
     'Create branches', 'Create a branch for the current tenant.', true),
    ('branch.location.update', 'branches', 'update',
     'Update branches', 'Update branch profile information.', true),
    ('branch.location.select', 'branches', 'select',
     'Select branch', 'Switch the active branch within the current tenant.', true),

    ('user.profile.view', 'users', 'view',
     'View profile', 'View the current user profile.', true),
    ('user.profile.update', 'users', 'update',
     'Update profile', 'Update normal current-user profile fields.', true),
    ('user.branch.select', 'users', 'select',
     'Select user branch', 'Assign the current session to a tenant branch.', true),
    ('user.role.view', 'users', 'view',
     'View roles', 'View tenant roles and user-role assignments.', true),
    ('user.role.manage', 'users', 'manage',
     'Manage roles', 'Manage tenant roles and role assignments.', true),

    ('inventory.product.view', 'inventory', 'view',
     'View products', 'View products, prices, and availability.', true),
    ('inventory.product.create', 'inventory', 'create',
     'Create products', 'Create products and initial stock.', true),
    ('inventory.product.update', 'inventory', 'update',
     'Update products', 'Update product details, prices, and tracking mode.', true),
    ('inventory.product.delete', 'inventory', 'delete',
     'Delete products', 'Delete products through the existing product flow.', true),
    ('inventory.category.view', 'inventory', 'view',
     'View categories', 'View product categories.', true),
    ('inventory.category.manage', 'inventory', 'manage',
     'Manage categories', 'Create and maintain product categories.', true),
    ('inventory.stock.view', 'inventory', 'view',
     'View stock', 'View branch inventory and low-stock information.', true),
    ('inventory.stock.adjust', 'inventory', 'adjust',
     'Adjust stock', 'Record inventory stock adjustments.', true),
    ('inventory.imei.view', 'inventory', 'view',
     'View IMEI units', 'View individually tracked inventory units.', true),
    ('inventory.imei.manage', 'inventory', 'manage',
     'Manage IMEI units', 'Create and maintain IMEI-tracked units.', true),
    ('inventory.price_history.view', 'inventory', 'view',
     'View price history', 'View historical product sale-price changes.', true),
    ('inventory.barcode.scan', 'inventory', 'scan',
     'Scan product barcodes', 'Use camera or physical barcode input.', true),

    ('pos.sale.view', 'pos', 'view',
     'View sales', 'View point-of-sale transactions.', true),
    ('pos.sale.create', 'pos', 'create',
     'Create sales', 'Complete a point-of-sale transaction.', true),
    ('pos.sale.hold', 'pos', 'hold',
     'Hold carts', 'Hold and restore point-of-sale carts.', true),
    ('pos.sale.void', 'pos', 'void',
     'Void sales', 'Void an eligible sale.', true),
    ('pos.sale.return', 'pos', 'return',
     'Return sales', 'Create an eligible sale return.', true),
    ('pos.discount.apply', 'pos', 'apply',
     'Apply discounts', 'Apply discounts within the current limits.', true),
    ('pos.discount.approve', 'pos', 'approve',
     'Approve discounts', 'Approve discounts requiring authorization.', true),
    ('pos.payment.create', 'pos', 'create',
     'Record sale payments', 'Record payments while completing a sale.', true),

    ('customer.customer.view', 'customers', 'view',
     'View customers', 'View customers belonging to the tenant.', true),
    ('customer.customer.create', 'customers', 'create',
     'Create customers', 'Create a customer in a tenant branch.', true),
    ('customer.customer.update', 'customers', 'update',
     'Update customers', 'Update customer profile and credit details.', true),
    ('customer.credit.view', 'customers', 'view',
     'View customer credit', 'View limits, balances, and customer history.', true),
    ('customer.credit.update', 'customers', 'update',
     'Update credit limits', 'Update a customer credit limit.', true),
    ('customer.credit.settle', 'customers', 'settle',
     'Settle customer credit', 'Record a customer balance settlement.', true),

    ('repair.ticket.view', 'repairs', 'view',
     'View repairs', 'View repair tickets and status history.', true),
    ('repair.ticket.create', 'repairs', 'create',
     'Create repairs', 'Create a repair ticket and intake record.', true),
    ('repair.ticket.update', 'repairs', 'update',
     'Update repairs', 'Update repair ticket details.', true),
    ('repair.status.update', 'repairs', 'update',
     'Update repair status', 'Move a repair ticket through its workflow.', true),
    ('repair.payment.create', 'repairs', 'create',
     'Record repair payments', 'Record payments against repair work.', true),

    ('supplier.supplier.view', 'suppliers', 'view',
     'View suppliers', 'View supplier records and balances.', true),
    ('supplier.supplier.create', 'suppliers', 'create',
     'Create suppliers', 'Create a supplier record.', true),
    ('supplier.supplier.update', 'suppliers', 'update',
     'Update suppliers', 'Update supplier details and catalog links.', true),
    ('supplier.payment.create', 'suppliers', 'create',
     'Record supplier payments', 'Record payments made to suppliers.', true),

    ('purchase.order.view', 'purchases', 'view',
     'View purchase orders', 'View purchase orders and receiving status.', true),
    ('purchase.order.create', 'purchases', 'create',
     'Create purchase orders', 'Create supplier purchase orders.', true),
    ('purchase.order.update', 'purchases', 'update',
     'Update purchase orders', 'Update eligible purchase orders.', true),
    ('purchase.order.receive', 'purchases', 'receive',
     'Receive purchases', 'Record goods received against a purchase order.', true),

    ('expense.expense.view', 'expenses', 'view',
     'View expenses', 'View tenant expense records.', true),
    ('expense.expense.create', 'expenses', 'create',
     'Create expenses', 'Create manual expense records.', true),
    ('expense.expense.update', 'expenses', 'update',
     'Update expenses', 'Update eligible expense records.', true),
    ('expense.expense.void', 'expenses', 'void',
     'Void expenses', 'Void a confirmed expense.', true),
    ('expense.category.manage', 'expenses', 'manage',
     'Manage expense categories', 'Create and maintain expense categories.', true),
    ('expense.recurring.manage', 'expenses', 'manage',
     'Manage recurring expenses', 'Create and maintain recurring expense rules.', true),

    ('account.account.view', 'accounts', 'view',
     'View accounts', 'View cash, bank, wallet, and other accounts.', true),
    ('account.account.create', 'accounts', 'create',
     'Create accounts', 'Create financial accounts.', true),
    ('account.account.update', 'accounts', 'update',
     'Update accounts', 'Update financial account details.', true),
    ('account.transaction.view', 'accounts', 'view',
     'View account transactions', 'View account transaction history.', true),
    ('account.transaction.create', 'accounts', 'create',
     'Create account transactions', 'Record account inflow and outflow.', true),

    ('report.sales.view', 'reports', 'view',
     'View sales reports', 'View sales reporting and analytics.', true),
    ('report.sales.export', 'reports', 'export',
     'Export sales reports', 'Export sales report output.', true),
    ('report.sales.schedule', 'reports', 'schedule',
     'Schedule sales reports', 'Schedule sales report delivery.', true),
    ('report.business.view', 'reports', 'view',
     'View business reports', 'View revenue, expense, and profit reporting.', true),
    ('report.business.export', 'reports', 'export',
     'Export business reports', 'Export business report output.', true),
    ('report.business.schedule', 'reports', 'schedule',
     'Schedule business reports', 'Schedule business report delivery.', true),
    ('report.all_branches.view', 'reports', 'view',
     'View all-branch reports', 'View combined reporting across tenant branches.', true),

    ('setting.shop.view', 'settings', 'view',
     'View shop settings', 'View tenant shop settings.', true),
    ('setting.shop.update', 'settings', 'update',
     'Update shop settings', 'Update normal tenant shop fields.', true),
    ('setting.branch.view', 'settings', 'view',
     'View branch settings', 'View branch profile settings.', true),
    ('setting.branch.update', 'settings', 'update',
     'Update branch settings', 'Update a branch profile.', true),

    ('receipt.receipt.view', 'receipts', 'view',
     'View receipts', 'View generated sale receipts.', true),
    ('receipt.receipt.print', 'receipts', 'print',
     'Print receipts', 'Print receipts using configured desktop printing.', true),
    ('receipt.receipt.send', 'receipts', 'send',
     'Send receipts', 'Send receipts through an available delivery channel.', true)
  on conflict (key) do update
  set module = excluded.module,
      action = excluded.action,
      name = excluded.name,
      description = excluded.description,
      is_active = excluded.is_active;
end
$function$;

revoke all on function public.sync_global_permission_catalog() from public;
revoke all on function public.sync_global_permission_catalog() from anon;
revoke all on function public.sync_global_permission_catalog() from authenticated;

select public.sync_global_permission_catalog();
