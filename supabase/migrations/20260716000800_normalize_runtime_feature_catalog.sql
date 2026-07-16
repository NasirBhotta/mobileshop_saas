-- Register the tenant app's commercially configurable runtime capabilities.
-- Core actions continue to inherit their parent module access and are not
-- exposed as separate commercial switches.

insert into public.features (key, module, name, description, is_active)
values
  ('inventory.stock_adjustments', 'inventory', 'Stock adjustments',
   'Create manual inventory stock adjustments.', true),
  ('inventory.imei_tracking', 'inventory', 'IMEI tracking',
   'Track serialized inventory by IMEI.', true),
  ('pos.returns', 'pos', 'POS returns',
   'Process point-of-sale returns.', true),
  ('pos.receipt_printing', 'pos', 'Receipt printing',
   'Print and reprint point-of-sale receipts.', true),
  ('pos.credit_sales', 'pos', 'Credit sales',
   'Complete point-of-sale transactions on customer credit.', true),
  ('pos.discounts', 'pos', 'POS discounts',
   'Apply discounts during checkout.', true),
  ('repairs.imei_linking', 'repairs', 'Repair IMEI linking',
   'Link repair tickets to device IMEI records.', true),
  ('expenses.receipts', 'expenses', 'Expense receipts',
   'Attach and manage receipts on expenses.', true),
  ('expenses.recurring', 'expenses', 'Recurring expenses',
   'Create and process recurring expense rules.', true),
  ('expenses.reporting', 'expenses', 'Expense reporting',
   'Access expense reporting tools.', true),
  ('accounts.transfers', 'accounts', 'Account transfers',
   'Transfer balances between financial accounts.', true),
  ('procurement.goods_receipts', 'purchases', 'Goods receiving',
   'Receive purchase-order stock into inventory.', true),
  ('procurement.supplier_payments', 'purchases', 'Supplier payments',
   'Record and manage supplier payments.', true),
  ('reports.business', 'reports', 'Business reports',
   'Access advanced business reporting views.', true)
on conflict do nothing;

-- Preserve the current product rule: implemented capabilities are available
-- on every package, except scheduled reports on Starter.
insert into public.plan_features (plan_id, feature_id, enabled, reason)
select p.id, f.id, true, 'Runtime feature catalog normalization'
from public.plans p
cross join public.features f
where p.key in ('starter', 'business', 'enterprise')
  and p.is_active and p.deleted_at is null
  and f.key in (
    'inventory.stock_adjustments', 'inventory.imei_tracking',
    'pos.returns', 'pos.receipt_printing', 'pos.credit_sales',
    'pos.discounts', 'repairs.imei_linking', 'expenses.receipts',
    'expenses.recurring', 'expenses.reporting', 'accounts.transfers',
    'procurement.goods_receipts', 'procurement.supplier_payments',
    'reports.business'
  )
on conflict (plan_id, feature_id) do nothing;

-- Starter keeps report export, while scheduled delivery remains a
-- Business/Enterprise capability.
update public.plan_features pf
set enabled = true,
    reason = 'Runtime feature catalog normalization'
from public.plans p, public.features f
where pf.plan_id = p.id
  and pf.feature_id = f.id
  and p.key in ('starter', 'business', 'enterprise')
  and f.key = 'reports.export';

update public.plan_features pf
set enabled = (p.key in ('business', 'enterprise')),
    reason = 'Runtime feature catalog normalization'
from public.plans p, public.features f
where pf.plan_id = p.id
  and pf.feature_id = f.id
  and p.key in ('starter', 'business', 'enterprise')
  and f.key = 'reports.scheduling';
