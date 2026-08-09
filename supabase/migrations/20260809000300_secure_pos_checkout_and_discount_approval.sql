-- Harden POS checkout trust boundaries without changing the current POS UI or
-- its intentional manual-price workflow.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.hash_user_approval_pin()
returns trigger
language plpgsql
security invoker
set search_path = public, extensions, pg_temp
as $function$
begin
  if new.approval_pin is not null
     and (tg_op = 'INSERT' or new.approval_pin is distinct from old.approval_pin)
     and new.approval_pin not like '$2%' then
    new.approval_pin := extensions.crypt(
      new.approval_pin,
      extensions.gen_salt('bf')
    );
  end if;
  return new;
end
$function$;

revoke all on function public.hash_user_approval_pin() from public, anon,
authenticated;

drop trigger if exists users_hash_approval_pin on public.users;
create trigger users_hash_approval_pin
before insert or update of approval_pin on public.users
for each row execute function public.hash_user_approval_pin();

-- Convert existing plaintext PINs once. bcrypt hashes already start with $2.
update public.users
set approval_pin = extensions.crypt(
  approval_pin,
  extensions.gen_salt('bf')
)
where approval_pin is not null
  and approval_pin not like '$2%';

create or replace function public.verify_pos_discount_approval(
  p_branch_id uuid,
  p_pin text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $function$
declare
  v_actor_tenant_id uuid;
  v_approver public.users%rowtype;
  v_permission_id uuid;
  v_role_id uuid;
  v_override boolean;
  v_allowed boolean := false;
begin
  if p_pin is null or length(trim(p_pin)) < 4 then
    return null;
  end if;

  select actor.tenant_id
  into v_actor_tenant_id
  from public.users actor
  join public.branches branch
    on branch.id = p_branch_id
   and branch.tenant_id = actor.tenant_id
  where actor.id = auth.uid()
    and actor.is_active
    and actor.deleted_at is null;

  if v_actor_tenant_id is null then
    return null;
  end if;

  select approver.*
  into v_approver
  from public.users approver
  where approver.tenant_id = v_actor_tenant_id
    and approver.is_active
    and approver.deleted_at is null
    and approver.approval_pin is not null
    and approver.approval_pin = extensions.crypt(
      trim(p_pin),
      approver.approval_pin
    )
  order by approver.id
  limit 1;

  if v_approver.id is null then
    return null;
  end if;
  if v_approver.role = 'owner' then
    return v_approver.id;
  end if;

  select permission.id
  into v_permission_id
  from public.permissions permission
  where permission.key = 'pos.discount.approve'
    and permission.is_active;
  if v_permission_id is null then
    return null;
  end if;

  if exists (
    select 1
    from public.user_branch_role_assignments assignment
    where assignment.tenant_id = v_actor_tenant_id
      and assignment.user_id = v_approver.id
  ) then
    select assignment.role_id
    into v_role_id
    from public.user_branch_role_assignments assignment
    join public.roles role
      on role.id = assignment.role_id
     and role.tenant_id = assignment.tenant_id
     and role.is_active
     and role.deleted_at is null
    where assignment.tenant_id = v_actor_tenant_id
      and assignment.user_id = v_approver.id
      and assignment.branch_id = p_branch_id
      and assignment.revoked_at is null
    limit 1;

    if v_role_id is not null then
      select override.is_allowed
      into v_override
      from public.user_branch_permission_overrides override
      where override.tenant_id = v_actor_tenant_id
        and override.user_id = v_approver.id
        and override.branch_id = p_branch_id
        and override.permission_id = v_permission_id;

      v_allowed := case
        when found then v_override
        else exists (
          select 1 from public.role_permissions role_permission
          where role_permission.role_id = v_role_id
            and role_permission.permission_id = v_permission_id
        )
      end;
    end if;
  else
    v_allowed := exists (
      select 1
      from public.user_role_assignments assignment
      join public.roles role
        on role.id = assignment.role_id
       and role.tenant_id = assignment.tenant_id
       and role.is_active
       and role.deleted_at is null
      join public.role_permissions role_permission
        on role_permission.role_id = role.id
      where assignment.tenant_id = v_actor_tenant_id
        and assignment.user_id = v_approver.id
        and assignment.revoked_at is null
        and role_permission.permission_id = v_permission_id
    );
  end if;

  return case when v_allowed then v_approver.id else null end;
end
$function$;

revoke all on function public.verify_pos_discount_approval(uuid, text)
from public, anon;
grant execute on function public.verify_pos_discount_approval(uuid, text)
to authenticated, service_role;

-- The legacy RPC is an internal implementation detail of v2. Prevent clients
-- from bypassing branch permission and account-ledger validation by calling it.
revoke execute on function public.commit_pos_sale(jsonb) from authenticated;

create or replace function public.validate_pos_sale_amounts(p_sale jsonb)
returns void
language plpgsql
immutable
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_item record;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_tax numeric := 0;
  v_total numeric := 0;
  v_line_total numeric;
begin
  if jsonb_typeof(p_sale->'sale_items') <> 'array'
     or jsonb_array_length(p_sale->'sale_items') = 0 then
    raise exception using errcode = '22023',
      message = 'Sale must contain at least one item.';
  end if;

  for v_item in
    select
      (value->>'quantity')::integer as quantity,
      (value->>'unit_price')::numeric as unit_price,
      coalesce((value->>'discount_amount')::numeric, 0) as discount_amount,
      coalesce((value->>'tax_rate')::numeric, 0) as tax_rate,
      (value->>'line_total')::numeric as submitted_line_total
    from jsonb_array_elements(p_sale->'sale_items')
  loop
    if v_item.quantity <= 0
       or v_item.unit_price < 0
       or v_item.discount_amount < 0
       or v_item.discount_amount > v_item.unit_price
       or v_item.tax_rate < 0
       or v_item.tax_rate > 100 then
      raise exception using errcode = '22023',
        message = 'Sale item amount, discount, or tax is invalid.';
    end if;

    v_line_total :=
      ((v_item.unit_price - v_item.discount_amount) * v_item.quantity)
      * (1 + v_item.tax_rate / 100);
    if abs(v_item.submitted_line_total - v_line_total) > 0.01 then
      raise exception using errcode = '22023',
        message = 'Sale item total does not match its price calculation.';
    end if;

    v_subtotal := v_subtotal + (v_item.unit_price * v_item.quantity);
    v_discount := v_discount + (v_item.discount_amount * v_item.quantity);
    v_tax := v_tax + (
      (v_item.unit_price - v_item.discount_amount)
      * v_item.quantity * v_item.tax_rate / 100
    );
  end loop;

  v_total := v_subtotal - v_discount + v_tax;
  if abs((p_sale->>'subtotal')::numeric - v_subtotal) > 0.01
     or abs((p_sale->>'discount_amount')::numeric - v_discount) > 0.01
     or abs((p_sale->>'tax_amount')::numeric - v_tax) > 0.01
     or abs((p_sale->>'total')::numeric - v_total) > 0.01 then
    raise exception using errcode = '22023',
      message = 'Sale totals do not match item calculations.';
  end if;
end
$function$;

-- Preserve commit_pos_sale_v2's established transaction and ledger behavior,
-- adding validation at its entry point without duplicating that implementation.
alter function public.commit_pos_sale_v2(jsonb) rename to commit_pos_sale_v2_unvalidated;

create or replace function public.commit_pos_sale_v2(p_sale jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.validate_pos_sale_amounts(p_sale);
  return public.commit_pos_sale_v2_unvalidated(p_sale);
end
$function$;

revoke all on function public.commit_pos_sale_v2_unvalidated(jsonb)
from public, anon, authenticated;
revoke all on function public.commit_pos_sale_v2(jsonb) from public, anon;
grant execute on function public.commit_pos_sale_v2(jsonb)
to authenticated, service_role;
