-- SEC-17 staging-only permission catalog seed.
-- Run only in the isolated staging project after its schema-only import.
-- This adds global permission definitions; it creates no production data,
-- tenant, branch, Auth user, product, sale or payment record.

begin;

select public.sync_global_permission_catalog();

commit;

-- Expected: all four entries are present and active.
select key, is_active
from public.permissions
where key in (
  'inventory.product.create',
  'inventory.product.update',
  'inventory.imei.manage',
  'account.transaction.create'
)
order by key;
