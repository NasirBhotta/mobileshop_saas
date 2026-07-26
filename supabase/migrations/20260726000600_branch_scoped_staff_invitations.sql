-- Add branch-role plans to staff invitations without changing the existing
-- Auth invitation or compatibility-role completion flow.

create table public.staff_invitation_branch_roles (
  invitation_id uuid not null references public.staff_invitations(id)
    on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null,
  role_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (invitation_id, branch_id),
  constraint staff_invite_branch_roles_branch_tenant_fkey
    foreign key (branch_id, tenant_id)
    references public.branches(id, tenant_id)
    on delete restrict,
  constraint staff_invite_branch_roles_role_tenant_fkey
    foreign key (role_id, tenant_id)
    references public.roles(id, tenant_id)
    on delete restrict
);

alter table public.staff_invitation_branch_roles enable row level security;
revoke all on table public.staff_invitation_branch_roles
from public, anon, authenticated;

create or replace function public.set_staff_invitation_branch_roles(
  p_invitation_id uuid,
  p_branch_roles jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_tenant_owner();
  requested_count integer;
  valid_count integer;
begin
  if p_branch_roles is null
     or jsonb_typeof(p_branch_roles) <> 'object'
     or p_branch_roles = '{}'::jsonb then
    raise exception using
      errcode = '22023',
      message = 'At least one branch role is required.';
  end if;

  if not exists (
    select 1
    from public.staff_invitations invitation
    where invitation.id = p_invitation_id
      and invitation.tenant_id = actor_tenant_id
      and invitation.invited_by = auth.uid()
      and invitation.status = 'pending'
      and invitation.expires_at > now()
  ) then
    raise exception using
      errcode = '42501',
      message = 'A pending invitation created by this owner is required.';
  end if;

  select
    count(*),
    count(*) filter (where branch.id is not null and role.id is not null)
  into requested_count, valid_count
  from jsonb_each_text(p_branch_roles) entry
  left join public.branches branch
    on branch.id = entry.key::uuid
   and branch.tenant_id = actor_tenant_id
   and branch.is_active
  left join public.roles role
    on role.id = entry.value::uuid
   and role.tenant_id = actor_tenant_id
   and role.is_active
   and role.deleted_at is null
   and not (role.is_system and role.code = 'owner');

  if requested_count <> valid_count then
    raise exception using
      errcode = '42501',
      message = 'Every invitation branch role must be active and tenant-safe.';
  end if;

  delete from public.staff_invitation_branch_roles
  where invitation_id = p_invitation_id;

  insert into public.staff_invitation_branch_roles (
    invitation_id, tenant_id, branch_id, role_id
  )
  select
    p_invitation_id,
    actor_tenant_id,
    entry.key::uuid,
    entry.value::uuid
  from jsonb_each_text(p_branch_roles) entry;
end
$function$;

create or replace function public.install_staff_invitation_branch_roles()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if old.status = 'pending'
     and new.status = 'accepted'
     and new.invited_user_id is not null then
    insert into public.user_branch_role_assignments (
      tenant_id, user_id, branch_id, role_id, assigned_by
    )
    select
      planned.tenant_id,
      new.invited_user_id,
      planned.branch_id,
      planned.role_id,
      new.invited_by
    from public.staff_invitation_branch_roles planned
    where planned.invitation_id = new.id;
  end if;
  return new;
end
$function$;

create trigger staff_invitations_install_branch_roles
after update of status, invited_user_id on public.staff_invitations
for each row execute function public.install_staff_invitation_branch_roles();

revoke all on function public.set_staff_invitation_branch_roles(uuid, jsonb)
from public, anon;
grant execute on function public.set_staff_invitation_branch_roles(uuid, jsonb)
to authenticated;
revoke all on function public.install_staff_invitation_branch_roles()
from public, anon, authenticated;
