-- Security Patch 6: enforce tenant isolation on public.branches while keeping
-- onboarding, tenant-wide branch access, branch selection, and settings intact.

alter table public.branches enable row level security;

drop policy if exists "branches_select_own_tenant" on public.branches;
create policy "branches_select_own_tenant"
on public.branches
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = branches.tenant_id
  )
);

drop policy if exists "branches_insert_owned_tenant" on public.branches;
create policy "branches_insert_owned_tenant"
on public.branches
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = branches.tenant_id
  )
);

drop policy if exists "branches_update_own_tenant" on public.branches;
create policy "branches_update_own_tenant"
on public.branches
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = branches.tenant_id
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = branches.tenant_id
  )
);

-- Intentionally no DELETE policy. Branch selection remains a users.branch_id
-- update and can select any visible branch belonging to the user's tenant.

-- Rollback (restores the pre-patch effective state while leaving branch
-- policies available but inactive):
-- alter table public.branches disable row level security;
