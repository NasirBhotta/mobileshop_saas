-- Security Patch 5: enforce tenant isolation on public.tenants while retaining
-- the current authenticated onboarding and owner settings flows.

alter table public.tenants enable row level security;

drop policy if exists "tenants_insert_during_own_setup" on public.tenants;
create policy "tenants_insert_during_own_setup"
on public.tenants
for insert
to authenticated
with check (
  id = auth.uid()
  and setup_complete = false
  and plan = 'starter'
  and status = 'active'
  and exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'owner'
      and (u.tenant_id is null or u.tenant_id = tenants.id)
  )
);

drop policy if exists "tenants_select_own_tenant" on public.tenants;
create policy "tenants_select_own_tenant"
on public.tenants
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and (
        u.tenant_id = tenants.id
        or (
          u.role = 'owner'
          and u.tenant_id is null
          and tenants.id = auth.uid()
          and tenants.setup_complete = false
        )
      )
  )
);

drop policy if exists "tenants_update_owned_tenant" on public.tenants;
create policy "tenants_update_owned_tenant"
on public.tenants
for update
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'owner'
      and (
        u.tenant_id = tenants.id
        or (
          u.tenant_id is null
          and tenants.id = auth.uid()
          and tenants.setup_complete = false
        )
      )
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'owner'
      and (
        u.tenant_id = tenants.id
        or (
          u.tenant_id is null
          and tenants.id = auth.uid()
          and tenants.setup_complete = false
        )
      )
  )
);

-- Intentionally no DELETE policy. Security Patch 4's
-- tenants_protect_subscription_fields trigger remains unchanged and continues
-- to reject authenticated plan/status changes with SQLSTATE 42501.

-- Rollback (restores the pre-patch effective state while leaving the three
-- pre-existing onboarding/tenant policies available but inactive):
-- alter table public.tenants disable row level security;
