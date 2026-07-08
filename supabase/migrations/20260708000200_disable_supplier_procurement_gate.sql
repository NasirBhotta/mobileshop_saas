-- Temporarily allow Supplier & Procurement for every tenant.
-- Keep tenant RLS intact; this only disables the plan/add-on gate.

create or replace function public.tenant_procurement_enabled(p_tenant_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select true
$$;

create or replace function public.ensure_procurement_enabled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return new;
end;
$$;
