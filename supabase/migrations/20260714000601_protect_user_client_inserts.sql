-- Security Patch 7 corrective guard: enforce the onboarding insert contract
-- even if the deployed database contains another permissive INSERT policy.

create or replace function public.protect_user_client_insert()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
begin
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  if new.id is distinct from auth.uid()
     or new.role is distinct from 'owner'
     or new.tenant_id is not null
     or new.branch_id is not null
     or new.approval_pin is not null then
    raise exception using
      errcode = '42501',
      message = 'Initial user profile must be the authenticated owner without tenant, branch, or approval PIN assignment.';
  end if;

  return new;
end
$function$;

revoke all on function public.protect_user_client_insert() from public;
revoke all on function public.protect_user_client_insert() from anon;
revoke all on function public.protect_user_client_insert() from authenticated;

drop trigger if exists users_protect_client_insert on public.users;
create trigger users_protect_client_insert
before insert on public.users
for each row
execute function public.protect_user_client_insert();

-- Rollback:
-- drop trigger if exists users_protect_client_insert on public.users;
-- drop function if exists public.protect_user_client_insert();
