-- Security Patch 7: restrict client-managed user fields while preserving the
-- existing profile, onboarding tenant-link, and branch-selection flows.

drop policy if exists "users_insert_own_profile" on public.users;
create policy "users_insert_own_profile"
on public.users
for insert
to authenticated
with check (
  id = auth.uid()
  and role = 'owner'
  and tenant_id is null
  and branch_id is null
  and approval_pin is null
);

drop policy if exists "users_update_own_setup_fields" on public.users;
create policy "users_update_own_setup_fields"
on public.users
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create or replace function public.protect_user_client_fields()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
declare
  tenant_link_allowed boolean := false;
  stale_tenant_clear_allowed boolean := false;
  old_protected jsonb;
  new_protected jsonb;
begin
  -- Trusted administration remains available for onboarding support and future
  -- server-side staff/role management. Client JWTs use authenticated instead.
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  if new.id is distinct from auth.uid() or old.id is distinct from auth.uid() then
    raise exception using
      errcode = '42501',
      message = 'Users may update only their own profile.';
  end if;

  if new.tenant_id is distinct from old.tenant_id then
    -- Current onboarding creates the owner profile first, then its tenant with
    -- the same auth UUID, and finally links the two. This is the only client
    -- tenant assignment that is permitted.
    tenant_link_allowed :=
      old.tenant_id is null
      and new.tenant_id = auth.uid()
      and old.role = 'owner'
      and new.role = 'owner'
      and exists (
        select 1
        from public.tenants t
        where t.id = auth.uid()
          and t.setup_complete = false
      );

    -- Preserve the app's stale-onboarding-reference recovery, but never allow
    -- a user to detach from a tenant row that still exists.
    stale_tenant_clear_allowed :=
      old.tenant_id is not null
      and new.tenant_id is null
      and old.role = 'owner'
      and new.role = 'owner'
      and not exists (
        select 1
        from public.tenants t
        where t.id = old.tenant_id
      );

    if not tenant_link_allowed and not stale_tenant_clear_allowed then
      raise exception using
        errcode = '42501',
        message = 'tenant_id can only be linked during initial owner onboarding.';
    end if;
  end if;

  -- Only these client fields are mutable. Comparing the remaining row as JSON
  -- also protects new sensitive columns added in a future migration by default.
  old_protected := to_jsonb(old) - array[
    'full_name', 'email', 'phone', 'branch_id', 'tenant_id'
  ];
  new_protected := to_jsonb(new) - array[
    'full_name', 'email', 'phone', 'branch_id', 'tenant_id'
  ];

  if new_protected is distinct from old_protected then
    raise exception using
      errcode = '42501',
      message = 'Only profile fields and branch selection may be updated.';
  end if;

  if new.branch_id is not null
     and new.branch_id is distinct from old.branch_id
     and not exists (
       select 1
       from public.branches b
       where b.id = new.branch_id
         and b.tenant_id = new.tenant_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'The selected branch must belong to the user tenant.';
  end if;

  return new;
end
$function$;

revoke all on function public.protect_user_client_fields() from public;
revoke all on function public.protect_user_client_fields() from anon;
revoke all on function public.protect_user_client_fields() from authenticated;

create trigger users_protect_client_fields
before update on public.users
for each row
execute function public.protect_user_client_fields();

-- Rollback:
-- drop trigger if exists users_protect_client_fields on public.users;
-- drop function if exists public.protect_user_client_fields();
-- Then restore users_insert_own_profile and users_update_own_setup_fields from
-- 20260702000000_setup_flow_rls.sql.
