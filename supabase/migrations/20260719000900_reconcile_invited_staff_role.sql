-- The public.users compatibility trigger creates a legacy assignment before
-- complete_staff_invitation() can install the selected role. Reconcile that
-- bootstrap assignment and make completion safe for same-role invitations.

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

revoke all on function public.complete_staff_invitation(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.complete_staff_invitation(uuid, uuid)
to service_role;
