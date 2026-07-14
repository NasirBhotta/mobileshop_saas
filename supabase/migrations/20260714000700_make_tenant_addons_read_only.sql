-- Security Patch 8: tenant add-ons are backend-managed and client-readable.
-- Procurement feature availability remains unchanged and is still enabled for
-- every tenant by 20260708000400_disable_supplier_procurement_gate_runtime.sql.

drop policy if exists "tenant users manage tenant addons"
on public.tenant_addons;

drop policy if exists "tenant users read own tenant addons"
on public.tenant_addons;
create policy "tenant users read own tenant addons"
on public.tenant_addons
for select
to authenticated
using (tenant_id = public.current_user_tenant_id());

-- PostgreSQL permissive policies are ORed. This restrictive SELECT guard keeps
-- tenant isolation effective even if another permissive deployed policy exists.
drop policy if exists "tenant addons tenant isolation guard"
on public.tenant_addons;
create policy "tenant addons tenant isolation guard"
on public.tenant_addons
as restrictive
for select
to authenticated
using (tenant_id = public.current_user_tenant_id());

-- Table privileges provide defense in depth against any unexpected permissive
-- write policy. service_role/backend privileges are intentionally untouched.
grant select on table public.tenant_addons to authenticated;
revoke insert, update, delete on table public.tenant_addons from authenticated;

-- Rollback:
-- drop policy if exists "tenant addons tenant isolation guard"
--   on public.tenant_addons;
-- drop policy if exists "tenant users read own tenant addons"
--   on public.tenant_addons;
-- create policy "tenant users manage tenant addons"
--   on public.tenant_addons for all
--   using (tenant_id = public.current_user_tenant_id())
--   with check (tenant_id = public.current_user_tenant_id());
-- grant insert, update, delete on table public.tenant_addons to authenticated;
