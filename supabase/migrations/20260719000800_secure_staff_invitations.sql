-- Secure owner-managed staff invitations. Auth administration remains in an
-- Edge Function; the Flutter client never receives the service-role secret.

create table public.staff_invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  email text not null,
  full_name text not null,
  role_id uuid not null,
  invited_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'failed', 'cancelled')),
  invited_user_id uuid references auth.users(id) on delete set null,
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint staff_invitations_role_tenant_fkey
    foreign key (role_id, tenant_id)
    references public.roles(id, tenant_id)
    on delete restrict,
  constraint staff_invitations_name_check check (length(trim(full_name)) > 0),
  constraint staff_invitations_email_check check (email = lower(trim(email)))
);

create unique index staff_invitations_pending_email_unique
on public.staff_invitations (lower(email))
where status = 'pending';

create index staff_invitations_tenant_created_idx
on public.staff_invitations (tenant_id, created_at desc);

alter table public.staff_invitations enable row level security;

revoke all on table public.staff_invitations from public, anon, authenticated;

create or replace function public.request_staff_invitation(
  p_email text,
  p_full_name text,
  p_role_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
  normalized_email text := lower(trim(p_email));
  normalized_name text := trim(p_full_name);
  invitation_id uuid;
begin
  if normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception using errcode = '22023', message = 'A valid email is required.';
  end if;
  if normalized_name is null or length(normalized_name) = 0 then
    raise exception using errcode = '22023', message = 'Full name is required.';
  end if;
  if exists (select 1 from public.users u where lower(u.email) = normalized_email) then
    raise exception using errcode = '23505', message = 'A user with this email already exists.';
  end if;
  if not exists (
    select 1
    from public.roles r
    where r.id = p_role_id
      and r.tenant_id = actor_tenant_id
      and r.is_active
      and r.deleted_at is null
      and not (r.is_system and r.code = 'owner')
  ) then
    raise exception using errcode = '42501', message = 'An active non-owner tenant role is required.';
  end if;

  update public.staff_invitations
  set status = 'cancelled', completed_at = now()
  where lower(email) = normalized_email
    and status = 'pending'
    and expires_at <= now();

  insert into public.staff_invitations (
    tenant_id, email, full_name, role_id, invited_by
  ) values (
    actor_tenant_id, normalized_email, normalized_name, p_role_id, auth.uid()
  )
  returning id into invitation_id;

  return invitation_id;
end
$function$;

create or replace function public.complete_staff_invitation(
  p_invitation_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  invitation public.staff_invitations%rowtype;
  auth_email text;
  compatibility_role text;
begin
  if auth.role() <> 'service_role' then
    raise exception using errcode = '42501', message = 'Service role required.';
  end if;

  select * into invitation
  from public.staff_invitations
  where id = p_invitation_id
  for update;

  if not found or invitation.status <> 'pending' or invitation.expires_at <= now() then
    raise exception using errcode = '22023', message = 'Invitation is no longer pending.';
  end if;

  select lower(trim(u.email)) into auth_email
  from auth.users u
  where u.id = p_user_id;
  if not found or auth_email is distinct from invitation.email then
    raise exception using errcode = '42501', message = 'Invited Auth user does not match the invitation.';
  end if;

  select case when r.code in ('manager', 'cashier') then r.code else 'cashier' end
  into compatibility_role
  from public.roles r
  where r.id = invitation.role_id
    and r.tenant_id = invitation.tenant_id
    and r.is_active
    and r.deleted_at is null
    and not (r.is_system and r.code = 'owner');
  if not found then
    raise exception using errcode = '42501', message = 'Invitation role is no longer assignable.';
  end if;

  insert into public.users (
    id, tenant_id, full_name, email, role, is_active, deleted_at
  ) values (
    p_user_id, invitation.tenant_id, invitation.full_name,
    invitation.email, compatibility_role, true, null
  );

  -- public.users has a compatibility trigger that may already have assigned
  -- the legacy manager/cashier role. Reconcile that bootstrap assignment so
  -- invited staff finishes with exactly the selected active role.
  update public.user_role_assignments
  set revoked_at = now()
  where tenant_id = invitation.tenant_id
    and user_id = p_user_id
    and role_id <> invitation.role_id
    and revoked_at is null;

  insert into public.user_role_assignments (tenant_id, user_id, role_id)
  values (invitation.tenant_id, p_user_id, invitation.role_id)
  on conflict (tenant_id, user_id, role_id) where revoked_at is null
  do nothing;

  update public.staff_invitations
  set status = 'accepted', invited_user_id = p_user_id, completed_at = now()
  where id = invitation.id;

  insert into public.role_management_audit_log (
    tenant_id, actor_user_id, action, role_id, target_user_id, details
  ) values (
    invitation.tenant_id, invitation.invited_by, 'user.invited',
    invitation.role_id, p_user_id,
    jsonb_build_object('email', invitation.email)
  );
end
$function$;

create or replace function public.fail_staff_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if auth.role() <> 'service_role' then
    raise exception using errcode = '42501', message = 'Service role required.';
  end if;
  update public.staff_invitations
  set status = 'failed', completed_at = now()
  where id = p_invitation_id and status = 'pending';
end
$function$;

revoke all on function public.request_staff_invitation(text, text, uuid) from public, anon;
grant execute on function public.request_staff_invitation(text, text, uuid) to authenticated;

revoke all on function public.complete_staff_invitation(uuid, uuid) from public, anon, authenticated;
grant execute on function public.complete_staff_invitation(uuid, uuid) to service_role;

revoke all on function public.fail_staff_invitation(uuid) from public, anon, authenticated;
grant execute on function public.fail_staff_invitation(uuid) to service_role;
