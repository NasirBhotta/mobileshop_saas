-- STAGING ONLY: seed the package/feature catalog needed to run the web app.
-- Run only in Supabase project diqwalqgfkusqefomtdl (staging).
-- This seeds catalog rows; it does not copy production data or alter app code.
-- Safe to re-run. It expects the synthetic SEC-17 tenant and current schema.

begin;

do $guard$
begin
  if not exists (
    select 1 from public.tenants
    where id = '11111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'Staging guard failed: SEC-17 synthetic tenant was not found.';
  end if;

  if to_regprocedure('public.sync_package_presets()') is null then
    raise exception 'Expected package seed function is missing; stop and report this error.';
  end if;
end;
$guard$;

-- Seeds starter/business/enterprise plans, core features, plan defaults,
-- and expense history limits from migration 20260715000600.
select public.sync_package_presets();

-- Runtime feature catalog additions from migration 20260716000800.
insert into public.features (key, module, name, description, is_active)
values
  ('inventory.stock_adjustments', 'inventory', 'Stock adjustments', 'Create manual inventory stock adjustments.', true),
  ('inventory.imei_tracking', 'inventory', 'IMEI tracking', 'Track serialized inventory by IMEI.', true),
  ('pos.returns', 'pos', 'POS returns', 'Process point-of-sale returns.', true),
  ('pos.receipt_printing', 'pos', 'Receipt printing', 'Print and reprint point-of-sale receipts.', true),
  ('pos.credit_sales', 'pos', 'Credit sales', 'Complete point-of-sale transactions on customer credit.', true),
  ('pos.discounts', 'pos', 'POS discounts', 'Apply discounts during checkout.', true),
  ('repairs.imei_linking', 'repairs', 'Repair IMEI linking', 'Link repair tickets to device IMEI records.', true),
  ('expenses.receipts', 'expenses', 'Expense receipts', 'Attach and manage receipts on expenses.', true),
  ('expenses.recurring', 'expenses', 'Recurring expenses', 'Create and process recurring expense rules.', true),
  ('expenses.reporting', 'expenses', 'Expense reporting', 'Access expense reporting tools.', true),
  ('accounts.transfers', 'accounts', 'Account transfers', 'Transfer balances between accounts.', true),
  ('procurement.goods_receipts', 'purchases', 'Goods receiving', 'Receive purchase-order stock into inventory.', true),
  ('procurement.supplier_payments', 'purchases', 'Supplier payments', 'Record and manage supplier payments.', true),
  ('reports.business', 'reports', 'Business reports', 'Access advanced business reporting views.', true)
on conflict do nothing;

insert into public.plan_features (plan_id, feature_id, enabled, reason)
select p.id, f.id, true, 'Staging web catalog seed (runtime defaults)'
from public.plans p
join public.features f on f.key in (
  'inventory.stock_adjustments', 'inventory.imei_tracking',
  'pos.returns', 'pos.receipt_printing', 'pos.credit_sales', 'pos.discounts',
  'repairs.imei_linking', 'expenses.receipts', 'expenses.recurring',
  'expenses.reporting', 'accounts.transfers', 'procurement.goods_receipts',
  'procurement.supplier_payments', 'reports.business'
)
where p.key in ('starter', 'business', 'enterprise')
  and p.is_active and p.deleted_at is null
on conflict (plan_id, feature_id) do update
set enabled = excluded.enabled,
    reason = excluded.reason,
    is_active = true,
    deleted_at = null,
    starts_at = null,
    expires_at = null,
    updated_at = now();

-- Match the current runtime defaults: report export is available on all
-- presets; scheduled reports are Business/Enterprise only.
update public.plan_features pf
set enabled = true, is_active = true, deleted_at = null,
    reason = 'Staging web catalog seed (runtime defaults)', updated_at = now()
from public.plans p, public.features f
where pf.plan_id = p.id and pf.feature_id = f.id
  and p.key in ('starter', 'business', 'enterprise')
  and f.key = 'reports.export';

update public.plan_features pf
set enabled = (p.key in ('business', 'enterprise')),
    is_active = true, deleted_at = null,
    reason = 'Staging web catalog seed (runtime defaults)', updated_at = now()
from public.plans p, public.features f
where pf.plan_id = p.id and pf.feature_id = f.id
  and p.key in ('starter', 'business', 'enterprise')
  and f.key = 'reports.scheduling';

-- Runtime entitlement added for Mobile Services in migration 20260725000500.
insert into public.features (key, module, name, description, is_active)
values (
  'mobile_services.access', 'mobile_services', 'Mobile Services',
  'Easypaisa and JazzCash send/receive services.', true
)
on conflict (lower(key)) do update
set module = excluded.module,
    name = excluded.name,
    description = excluded.description,
    is_active = true,
    deleted_at = null,
    updated_at = now();

insert into public.plan_features (plan_id, feature_id, enabled, reason)
select p.id, f.id, true, 'Staging web catalog seed (mobile services)'
from public.plans p
join public.features f on lower(f.key) = 'mobile_services.access'
where p.key in ('starter', 'business', 'enterprise')
  and p.is_active and p.deleted_at is null
on conflict (plan_id, feature_id) do update
set enabled = true,
    reason = excluded.reason,
    is_active = true,
    deleted_at = null,
    starts_at = null,
    expires_at = null,
    updated_at = now();

-- Verify the seeded catalog and the staging tenant's active dashboard plan row.
select jsonb_build_object(
  'active_plans', (
    select count(*) from public.plans
    where key in ('starter', 'business', 'enterprise')
      and is_active and deleted_at is null
  ),
  'active_features', (
    select count(*) from public.features where is_active and deleted_at is null
  ),
  'dashboard_access', (
    select jsonb_build_object(
      'tenant_plan', t.plan,
      'subscription_status', s.status,
      'feature_present', f.id is not null,
      'plan_feature_enabled', pf.enabled,
      'plan_feature_active', pf.is_active and pf.deleted_at is null
    )
    from public.tenants t
    left join public.tenant_subscriptions s
      on s.tenant_id = t.id and s.is_active and s.deleted_at is null
    left join public.plans p on p.id = s.plan_id
    left join public.features f on lower(f.key) = 'dashboard.access'
    left join public.plan_features pf
      on pf.plan_id = p.id and pf.feature_id = f.id
    where t.id = '11111111-1111-4111-8111-111111111111'
  )
) as staging_web_feature_catalog_seed;

commit;
