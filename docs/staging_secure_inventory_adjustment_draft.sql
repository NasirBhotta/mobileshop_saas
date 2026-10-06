-- STAGING-ONLY DRAFT: do not run in production.
-- Additive rollout step for SEC-17. It does NOT revoke direct table access,
-- replace RLS policies, or change an existing application call path.
-- Review against a fresh staging export before execution.

begin;

-- Record the authoritative resulting stock for idempotent RPC retries.
-- Nullable so existing direct-write history remains valid during transition.
alter table public.stock_adjustments
  add column if not exists result_quantity integer;

insert into public.permissions (key, module, action, name, description, is_active)
values (
  'inventory.stock.override', 'inventory', 'override', 'Override negative stock',
  'Allow an inventory adjustment to result in negative stock.', true
)
on conflict (key) do update
set is_active = true;

-- Only active tenant Owner roles receive the new negative-stock override.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key = 'inventory.stock.override'
where lower(r.code) = 'owner'
  and r.is_active
  and r.deleted_at is null
on conflict do nothing;

create or replace function public.adjust_inventory_stock_v2(p_adjustment jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_adjustment_id uuid := nullif(p_adjustment->>'id', '')::uuid;
  v_branch_id uuid := nullif(p_adjustment->>'branch_id', '')::uuid;
  v_product_id uuid := nullif(p_adjustment->>'product_id', '')::uuid;
  v_type text := lower(coalesce(p_adjustment->>'adjustment_type', ''));
  v_quantity integer := nullif(p_adjustment->>'quantity', '')::integer;
  v_reason text := nullif(btrim(coalesce(p_adjustment->>'reason', '')), '');
  v_reason_code text := nullif(btrim(coalesce(p_adjustment->>'reason_code', '')), '');
  v_reason_note text := nullif(btrim(coalesce(p_adjustment->>'reason_note', '')), '');
  v_override boolean := coalesce((p_adjustment->>'is_override')::boolean, false);
  v_tenant_id uuid;
  v_actor_id uuid := auth.uid();
  v_current_quantity integer;
  v_result_quantity integer;
  v_delta integer;
  v_product public.products%rowtype;
  v_existing public.stock_adjustments%rowtype;
begin
  if jsonb_typeof(p_adjustment) <> 'object'
     or v_adjustment_id is null
     or v_branch_id is null
     or v_product_id is null
     or v_quantity is null
     or v_quantity <= 0
     or v_type not in ('stock_in', 'stock_out')
     or v_reason is null
     or v_reason_code is null then
    raise exception using errcode = '22023',
      message = 'Inventory adjustment payload is invalid.';
  end if;

  -- Serialise retries that carry the same client-generated adjustment UUID.
  perform pg_advisory_xact_lock(hashtextextended(v_adjustment_id::text, 0));

  select b.tenant_id into v_tenant_id
  from public.branches b
  where b.id = v_branch_id;

  if v_tenant_id is null
     or not public.current_user_has_branch_permission(
       v_tenant_id, v_branch_id, 'inventory.stock.adjust'
     ) then
    raise exception using errcode = '42501',
      message = 'Inventory stock-adjust permission is required.';
  end if;

  if v_override and not public.current_user_has_branch_permission(
    v_tenant_id, v_branch_id, 'inventory.stock.override'
  ) then
    raise exception using errcode = '42501',
      message = 'Negative-stock override permission is required.';
  end if;

  -- A repeated request is safe only if it belongs to the same actor and has
  -- exactly the same immutable business fields.
  select * into v_existing
  from public.stock_adjustments
  where id = v_adjustment_id;
  if found then
    if v_existing.tenant_id = v_tenant_id
       and v_existing.branch_id = v_branch_id
       and v_existing.product_id = v_product_id
       and v_existing.adjustment_type = v_type
       and v_existing.quantity = v_quantity
       and v_existing.reason = v_reason
       and v_existing.reason_code = v_reason_code
       and coalesce(v_existing.reason_note, '') = coalesce(v_reason_note, '')
       and v_existing.is_override = v_override
       and v_existing.user_id = v_actor_id then
      return jsonb_build_object(
        'adjustment_id', v_adjustment_id,
        'quantity', v_existing.result_quantity,
        'duplicate', true
      );
    end if;
    raise exception using errcode = '23505',
      message = 'Adjustment id is already used with different contents.';
  end if;

  select * into v_product
  from public.products p
  where p.id = v_product_id
    and p.tenant_id = v_tenant_id
    and p.branch_id = v_branch_id;
  if v_product.id is null then
    raise exception using errcode = '22023',
      message = 'Product does not belong to this tenant and branch.';
  end if;

  v_delta := case when v_type = 'stock_in' then v_quantity else -v_quantity end;

  -- Lock an existing row. If it does not yet exist, race safely to create it.
  -- A stock-out cannot create a missing row, unless the authorized override
  -- explicitly permits a negative result.
  loop
    select i.quantity into v_current_quantity
    from public.inventory i
    where i.branch_id = v_branch_id and i.product_id = v_product_id
    for update;

    if found then
      v_result_quantity := v_current_quantity + v_delta;
      if v_result_quantity < 0 and not v_override then
        raise exception using errcode = '23514',
          message = 'Inventory cannot go below zero without an authorized override.';
      end if;
      update public.inventory
      set quantity = v_result_quantity, updated_at = now()
      where branch_id = v_branch_id and product_id = v_product_id;
      exit;
    end if;

    if v_delta < 0 and not v_override then
      raise exception using errcode = '23514',
        message = 'Inventory cannot go below zero without an authorized override.';
    end if;
    insert into public.inventory (
      branch_id, product_id, quantity, reorder_threshold, updated_at
    ) values (
      v_branch_id, v_product_id, v_delta, coalesce(v_product.reorder_threshold, 5), now()
    ) on conflict (branch_id, product_id) do nothing
    returning quantity into v_result_quantity;
    if found then
      exit;
    end if;
  end loop;

  insert into public.stock_adjustments (
    id, tenant_id, branch_id, product_id, adjustment_type, quantity,
    reason, adjusted_by, user_id, reason_code, reason_note, is_override,
    unit_cost, total_value, result_quantity
  ) values (
    v_adjustment_id, v_tenant_id, v_branch_id, v_product_id, v_type, v_quantity,
    v_reason, v_actor_id, v_actor_id, v_reason_code, v_reason_note, v_override,
    v_product.cost_price, v_product.cost_price * v_quantity, v_result_quantity
  );

  return jsonb_build_object(
    'adjustment_id', v_adjustment_id,
    'quantity', v_result_quantity,
    'duplicate', false
  );
end;
$function$;

revoke all on function public.adjust_inventory_stock_v2(jsonb) from public, anon;
grant execute on function public.adjust_inventory_stock_v2(jsonb) to authenticated;

commit;

-- Intentionally absent from this draft:
-- * any REVOKE on direct table CRUD grants
-- * any RLS policy replacement
-- * any change to existing app code or offline replay
-- Those belong only after staging client compatibility tests pass.
