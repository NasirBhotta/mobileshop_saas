-- Prevent configured staff from bypassing the filtered branch-selection UI.
-- Owners and staff without any branch configuration retain legacy behavior.

create or replace function public.enforce_user_branch_assignment_on_selection()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if new.branch_id is null
     or new.branch_id is not distinct from old.branch_id
     or new.role = 'owner' then
    return new;
  end if;

  if exists (
    select 1
    from public.user_branch_role_assignments configured
    where configured.tenant_id = new.tenant_id
      and configured.user_id = new.id
  ) and not exists (
    select 1
    from public.user_branch_role_assignments active_assignment
    where active_assignment.tenant_id = new.tenant_id
      and active_assignment.user_id = new.id
      and active_assignment.branch_id = new.branch_id
      and active_assignment.revoked_at is null
  ) then
    raise exception using
      errcode = '42501',
      message = 'The selected branch is not assigned to this user.';
  end if;

  return new;
end
$function$;

create trigger users_enforce_branch_selection_access
before update of branch_id on public.users
for each row
execute function public.enforce_user_branch_assignment_on_selection();

revoke all on function public.enforce_user_branch_assignment_on_selection()
from public, anon, authenticated;
