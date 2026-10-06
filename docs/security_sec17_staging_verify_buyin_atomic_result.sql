-- Read-only evidence check for the SEC-17 successful staging buy-in test.
-- Test purchase: fd3d0e7c-8208-4fd3-87c9-a745d27a261c
-- Expected: one purchase, one available unit, quantity 1, one ledger event,
-- and test-cash balance 38000.00 (50000.00 - 12000.00 exactly once).

with expected as (
  select
    'fd3d0e7c-8208-4fd3-87c9-a745d27a261c'::uuid as purchase_id,
    '0ff7b2db-d0e0-4372-a95c-a9a6d66d91a3'::uuid as product_id,
    '1ccd2367-83c0-4b32-b138-a4b9102a38fc'::uuid as inventory_unit_id,
    '33333333-3333-4333-8333-333333333333'::uuid as account_id
)
select jsonb_build_object(
  'purchase_rows', (select count(*) from public.customer_purchases p, expected e where p.id = e.purchase_id),
  'available_unit_rows', (select count(*) from public.inventory_units u, expected e where u.id = e.inventory_unit_id and u.status = 'available'),
  'inventory_quantity', (select i.quantity from public.inventory i, expected e where i.product_id = e.product_id and i.branch_id = '22222222-2222-4222-8222-222222222222'::uuid),
  'ledger_rows', (select count(*) from public.account_transactions t, expected e where t.source_event_key = 'customer_buyin:' || e.purchase_id::text),
  'account_balance', (select a.current_balance from public.accounts a, expected e where a.id = e.account_id),
  'atomicity_passed',
    (select count(*) = 1 from public.customer_purchases p, expected e where p.id = e.purchase_id)
    and (select count(*) = 1 from public.inventory_units u, expected e where u.id = e.inventory_unit_id and u.status = 'available')
    and (select i.quantity = 1 from public.inventory i, expected e where i.product_id = e.product_id and i.branch_id = '22222222-2222-4222-8222-222222222222'::uuid)
    and (select count(*) = 1 from public.account_transactions t, expected e where t.source_event_key = 'customer_buyin:' || e.purchase_id::text)
    and (select a.current_balance = 38000 from public.accounts a, expected e where a.id = e.account_id)
) as security_staging_buyin_atomic_result;
