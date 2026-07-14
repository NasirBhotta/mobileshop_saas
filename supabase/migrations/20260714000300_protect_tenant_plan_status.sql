-- Security Patch 4: tenant subscription state is server-managed.
--
-- Normal authenticated requests may continue updating all other tenant fields.
-- INSERT is intentionally unaffected so the existing onboarding flow can create
-- a starter/active tenant. Trusted database and service-role operations remain
-- available for a future billing backend.

create or replace function public.protect_tenant_subscription_fields()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
begin
  -- UPDATE payloads may contain unchanged plan/status values (for example an
  -- onboarding upsert). Preserve those existing successful operations.
  if new.plan is not distinct from old.plan
     and new.status is not distinct from old.status then
    return new;
  end if;

  -- Migrations/administration and a future trusted billing backend may manage
  -- subscription state. Client JWTs use the authenticated database role and
  -- therefore cannot satisfy this condition.
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  raise exception using
    errcode = '42501',
    message = 'Tenant plan and status can only be changed by a trusted billing service.';
end
$function$;

revoke all on function public.protect_tenant_subscription_fields() from public;
revoke all on function public.protect_tenant_subscription_fields() from anon;
revoke all on function public.protect_tenant_subscription_fields() from authenticated;

create trigger tenants_protect_subscription_fields
before update of plan, status on public.tenants
for each row
execute function public.protect_tenant_subscription_fields();

-- Rollback (restores only the objects added by Security Patch 4):
-- drop trigger if exists tenants_protect_subscription_fields on public.tenants;
-- drop function if exists public.protect_tenant_subscription_fields();
