-- The Flutter entitlement evaluator is the feature-access authority. Keep the
-- database trigger as tenant isolation only; stale plan/add-on gate definitions
-- otherwise reject valid PO and supplier-payment mutations.

create or replace function public.tenant_procurement_enabled(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tenants
    where id = p_tenant_id
  )
$$;

create or replace function public.ensure_procurement_enabled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tenant_procurement_enabled(new.tenant_id) then
    raise exception 'Tenant does not exist.';
  end if;

  return new;
end;
$$;
