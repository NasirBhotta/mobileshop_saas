-- Suppliers and their payable are branch-owned. Tenant-only filtering leaked
-- supplier cards and balances when a user switched between branches.

alter table public.suppliers
  drop constraint if exists suppliers_tenant_id_name_key;

create unique index if not exists idx_suppliers_branch_name_unique
  on public.suppliers(tenant_id, branch_id, lower(name))
  where branch_id is not null;

drop policy if exists "tenant users manage suppliers" on public.suppliers;
create policy "branch users manage suppliers"
on public.suppliers for all
using (
  tenant_id = public.current_user_tenant_id()
  and branch_id is not null
  and public.current_user_can_access_branch(branch_id)
)
with check (
  tenant_id = public.current_user_tenant_id()
  and branch_id is not null
  and public.current_user_can_access_branch(branch_id)
);

comment on column public.suppliers.branch_id is
  'Owning branch. Supplier cards, payable, orders and payments are branch scoped.';
