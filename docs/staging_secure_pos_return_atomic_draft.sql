-- STAGING-ONLY migration. Run against the staging project, never production.
-- SEC-17 atomic POS return boundary. Additive columns/RPC; no table grants or RLS are revoked.

begin;

alter table public.sale_returns
  add column if not exists request_fingerprint text;

alter table public.sale_return_items
  -- Stable client ID is staged on pending rows before the returned product exists.
  add column if not exists restock_product_id uuid,
  add column if not exists restock_condition text not null default 'returned',
  add column if not exists resale_price numeric;

insert into public.permissions (key, module, action, name, description, is_active)
values ('pos.return.approve', 'pos', 'approve', 'Approve returns',
  'Approve a pending POS sale return.', true)
on conflict (key) do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key = 'pos.return.approve'
where r.is_system and r.is_active and r.deleted_at is null
  and r.code in ('owner', 'manager')
on conflict (role_id, permission_id) do nothing;

insert into public.permissions (key, module, action, name, description, is_active)
values ('pos.return.override', 'pos', 'override', 'Override return window',
  'Allow a return outside the configured return window.', true)
on conflict (key) do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key = 'pos.return.override'
where r.is_system and r.is_active and r.deleted_at is null and r.code = 'owner'
on conflict (role_id, permission_id) do nothing;

create or replace function public.commit_pos_return_v2(p_return jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_id uuid := nullif(p_return->>'id', '')::uuid;
  v_sale_id uuid := nullif(p_return->>'original_sale_id', '')::uuid;
  v_branch_id uuid := nullif(p_return->>'branch_id', '')::uuid;
  v_requested_status text := coalesce(p_return->>'status', '');
  v_method text := lower(coalesce(p_return->>'refund_method', ''));
  v_amount numeric := coalesce(nullif(p_return->>'refund_amount', '')::numeric, 0);
  v_actor uuid := auth.uid();
  v_tenant uuid;
  v_return_window_days integer := 7;
  v_return_approval_threshold numeric := 25000;
  v_sale public.sales%rowtype;
  v_return public.sale_returns%rowtype;
  v_source_product public.products%rowtype;
  v_restock_product public.products%rowtype;
  v_existing boolean := false;
  v_same_request_fingerprint text;
  v_final_fingerprint text;
  v_item jsonb;
  v_original record;
  v_return_item public.sale_return_items%rowtype;
  v_restock_id uuid;
  v_qty integer;
  v_item_refund numeric;
  v_restock_condition text;
  v_unit_value numeric;
  v_sku text;
  v_refund_legs jsonb := coalesce(p_return->'refund_legs', '[]'::jsonb);
begin
  if jsonb_typeof(p_return) <> 'object'
     or v_id is null or v_sale_id is null or v_branch_id is null or v_actor is null
     or v_requested_status not in ('pending_approval', 'approved')
     or v_method not in ('cash', 'credit') or v_amount < 0
     or jsonb_typeof(p_return->'items') is distinct from 'array'
     or jsonb_array_length(p_return->'items') = 0
     or jsonb_typeof(v_refund_legs) <> 'array' then
    raise exception using errcode = '22023', message = 'POS return payload is invalid.';
  end if;

  -- Status, approver and cash allocation can change while a pending return is
  -- approved. Keep a pending fingerprint and a final approved fingerprint.
  v_same_request_fingerprint := md5((p_return - 'status' - 'approved_by' - 'refund_legs')::text);
  v_final_fingerprint := md5((p_return - 'status' - 'approved_by')::text);
  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

  select s.* into v_sale
  from public.sales s where s.id = v_sale_id for update;
  select b.tenant_id into v_tenant
  from public.branches b where b.id = v_branch_id and b.is_active;
  if v_sale.id is null or v_tenant is null or v_sale.branch_id <> v_branch_id
     or not public.current_user_has_branch_permission(v_tenant, v_branch_id, 'pos.sale.return') then
    raise exception using errcode = '42501', message = 'POS return permission or original sale context is invalid.';
  end if;

  select r.* into v_return
  from public.sale_returns r where r.id = v_id for update;
  v_existing := found;
  if v_existing and v_return.status = 'approved' then
    if v_return.request_fingerprint is distinct from v_final_fingerprint then
      raise exception using errcode = '23505', message = 'Approved return is immutable; request contents differ.';
    end if;
    return jsonb_build_object('return_id', v_id, 'status', 'approved', 'duplicate', true);
  end if;

  select coalesce(ts.return_window_days, 7), coalesce(ts.return_approval_threshold, 25000)
    into v_return_window_days, v_return_approval_threshold
  from public.tenant_settings ts where ts.tenant_id = v_tenant;
  v_return_window_days := coalesce(v_return_window_days, 7);
  v_return_approval_threshold := coalesce(v_return_approval_threshold, 25000);
  if now() > v_sale.created_at + make_interval(days => v_return_window_days)
     and (not public.current_user_has_branch_permission(v_tenant, v_branch_id, 'pos.return.override')
       or nullif(btrim(p_return->>'override_reason'), '') is null) then
    raise exception using errcode = '42501', message = 'Return window expired; authorized override and reason are required.';
  end if;

  if not v_existing then
    if nullif(p_return->>'user_id', '')::uuid is distinct from v_actor then
      raise exception using errcode = '42501', message = 'Return creator must match the authenticated user.';
    end if;
    if v_requested_status = 'approved' and v_amount > v_return_approval_threshold
       and not public.current_user_has_branch_permission(v_tenant, v_branch_id, 'pos.return.approve') then
      raise exception using errcode = '42501', message = 'Returns above the approval threshold require an authorized approver.';
    end if;
  elsif v_return.status = 'pending_approval' and v_requested_status = 'pending_approval' then
    -- Exact retries of a pending request are idempotent. The stored fingerprint
    -- excludes refund_legs because the actual cash allocation is supplied only
    -- when an authorized user approves; a pending retry makes no state changes.
    if v_return.user_id is distinct from v_actor
       or v_return.original_sale_id <> v_sale_id or v_return.branch_id <> v_branch_id
       or v_return.refund_method <> v_method or v_return.refund_amount <> v_amount
       or v_return.override_reason is distinct from nullif(p_return->>'override_reason', '')
       or v_return.refund_payment_id is distinct from nullif(p_return->>'refund_payment_id', '')::uuid
       or v_return.request_fingerprint is distinct from v_same_request_fingerprint then
      raise exception using errcode = '23505', message = 'Pending return retry differs from the stored request.';
    end if;
    return jsonb_build_object('return_id', v_id, 'status', 'pending_approval', 'duplicate', true);
  else
    if v_return.status <> 'pending_approval' or v_requested_status <> 'approved'
       or v_return.original_sale_id <> v_sale_id or v_return.branch_id <> v_branch_id
       or v_return.refund_method <> v_method or v_return.refund_amount <> v_amount
       or v_return.override_reason is distinct from nullif(p_return->>'override_reason', '')
       or v_return.refund_payment_id is distinct from nullif(p_return->>'refund_payment_id', '')::uuid
       or v_return.request_fingerprint is distinct from v_same_request_fingerprint then
      raise exception using errcode = '23505', message = 'Approval does not match the stored pending return.';
    end if;
    if not public.current_user_has_branch_permission(v_tenant, v_branch_id, 'pos.return.approve') then
      raise exception using errcode = '42501', message = 'Return approval permission is required.';
    end if;
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_return->'items') x
    group by (x->>'product_id')::uuid having count(*) > 1
  ) then
    raise exception using errcode = '22023', message = 'A product may appear only once in a return.';
  end if;

  -- Parent is inserted before child rows for the existing foreign key. Any
  -- validation or refund error later aborts both because this RPC is one transaction.
  if not v_existing then
    insert into public.sale_returns(
      id, original_sale_id, branch_id, user_id, status, refund_method, refund_amount,
      refund_payment_id, approval_required_reason, override_reason, approved_by,
      created_at, request_fingerprint
    ) values (
      v_id, v_sale_id, v_branch_id, v_actor, v_requested_status, v_method, v_amount,
      nullif(p_return->>'refund_payment_id', '')::uuid,
      nullif(p_return->>'approval_required_reason', ''), nullif(p_return->>'override_reason', ''),
      case when v_requested_status = 'approved' then v_actor end,
      coalesce(nullif(p_return->>'created_at', '')::timestamptz, now()),
      case when v_requested_status = 'approved' then v_final_fingerprint else v_same_request_fingerprint end
    );
  end if;

  for v_item in select value from jsonb_array_elements(p_return->'items') loop
    v_qty := nullif(v_item->>'quantity', '')::integer;
    v_item_refund := coalesce(nullif(v_item->>'refund_amount', '')::numeric, 0);
    v_restock_id := nullif(v_item->>'restock_product_id', '')::uuid;
    v_restock_condition := coalesce(nullif(btrim(v_item->>'restock_condition'), ''), 'returned');
    if v_qty is null or v_qty <= 0 or v_item_refund < 0 or v_restock_id is null then
      raise exception using errcode = '22023', message = 'Return item identity, quantity, refund, or restock ID is invalid.';
    end if;

    select si.product_id, sum(si.quantity)::integer as sold_qty,
      sum(si.line_total) as sold_total, max(si.product_name) as product_name,
      max(si.product_sku) as product_sku
    into v_original
    from public.sale_items si
    where si.sale_id = v_sale_id and si.product_id = (v_item->>'product_id')::uuid
    group by si.product_id;
    if v_original.product_id is null then
      raise exception using errcode = '22023', message = 'Return item is not part of the original sale.';
    end if;

    if coalesce((select sum(ri.quantity) from public.sale_return_items ri
      join public.sale_returns r on r.id = ri.return_id
      where ri.original_sale_id = v_sale_id and ri.product_id = v_original.product_id
        and r.status <> 'rejected' and ri.return_id <> v_id), 0) + v_qty > v_original.sold_qty then
      raise exception using errcode = '23514', message = 'Return quantity exceeds the unreturned original sale quantity.';
    end if;
    if v_item_refund > (v_original.sold_total * v_qty / v_original.sold_qty) + 0.01 then
      raise exception using errcode = '23514', message = 'Item refund exceeds its original sale value.';
    end if;

    select p.* into v_source_product
    from public.products p
    where p.id = v_original.product_id and p.tenant_id = v_tenant and p.branch_id = v_branch_id;
    if v_source_product.id is null then
      raise exception using errcode = '22023', message = 'Original product is outside the sale tenant and branch.';
    end if;

    if exists (select 1 from public.sale_return_items ri
      where ri.restock_product_id = v_restock_id and ri.return_id <> v_id) then
      raise exception using errcode = '23505', message = 'Restock product ID is already used by another return.';
    end if;

    if v_existing then
      select ri.* into v_return_item
      from public.sale_return_items ri
      where ri.return_id = v_id and ri.product_id = v_original.product_id
      for update;
      if not found or v_return_item.quantity <> v_qty or v_return_item.refund_amount <> v_item_refund
         or v_return_item.restock_product_id is distinct from v_restock_id
         or v_return_item.restock_condition <> v_restock_condition then
        raise exception using errcode = '23505', message = 'Approval item differs from the stored pending item.';
      end if;
    else
      insert into public.sale_return_items(
        return_id, original_sale_id, product_id, product_name, product_sku,
        quantity, refund_amount, restock_product_id, restock_condition, resale_price
      ) values (
        v_id, v_sale_id, v_original.product_id, v_original.product_name, v_original.product_sku,
        v_qty, v_item_refund, v_restock_id, v_restock_condition,
        v_item_refund / v_qty
      );
    end if;
  end loop;

  if (select count(*) from public.sale_return_items ri where ri.return_id = v_id)
      <> jsonb_array_length(p_return->'items') then
    raise exception using errcode = '23505', message = 'Return item set differs from the stored request.';
  end if;
  if abs((select coalesce(sum((x->>'refund_amount')::numeric), 0)
      from jsonb_array_elements(p_return->'items') x) - v_amount) > 0.01 then
    raise exception using errcode = '22023', message = 'Item refunds must sum to the return refund amount.';
  end if;

  if v_requested_status = 'pending_approval' then
    if v_existing then
      return jsonb_build_object('return_id', v_id, 'status', 'pending_approval', 'duplicate', true);
    end if;
    return jsonb_build_object('return_id', v_id, 'status', 'pending_approval', 'duplicate', false);
  end if;

  if v_existing then
    update public.sale_returns set status = 'approved', approved_by = v_actor,
      request_fingerprint = v_final_fingerprint where id = v_id;
  end if;

  for v_item in select value from jsonb_array_elements(p_return->'items') loop
    v_qty := (v_item->>'quantity')::integer;
    v_item_refund := coalesce((v_item->>'refund_amount')::numeric, 0);
    v_restock_id := (v_item->>'restock_product_id')::uuid;
    v_unit_value := v_item_refund / v_qty;
    select p.* into v_source_product from public.products p
    where p.id = (v_item->>'product_id')::uuid and p.tenant_id = v_tenant and p.branch_id = v_branch_id;

    perform pg_advisory_xact_lock(hashtextextended(v_restock_id::text, 0));
    select p.* into v_restock_product from public.products p where p.id = v_restock_id for update;
    if v_restock_product.id is null then
      v_sku := case when nullif(btrim(v_source_product.sku), '') is null
        then 'RTN-' || left(replace(v_restock_id::text, '-', ''), 8)
        else v_source_product.sku || '-RTN-' || left(replace(v_restock_id::text, '-', ''), 8) end;
      insert into public.products(
        id, tenant_id, branch_id, category_id, name, sku, description,
        sale_price, cost_price, imei_tracked, is_active, reorder_threshold,
        source_product_id, updated_at
      ) values (
        v_restock_id, v_tenant, v_branch_id, null, 'Returned - ' || v_source_product.name,
        v_sku, 'Returned stock from sale ' || v_sale_id::text || '.',
        v_unit_value, v_unit_value,
        false, true, v_source_product.reorder_threshold, v_source_product.id, now()
      ) returning * into v_restock_product;
    elsif v_restock_product.tenant_id <> v_tenant or v_restock_product.branch_id <> v_branch_id
       or v_restock_product.source_product_id is distinct from v_source_product.id then
      raise exception using errcode = '23505', message = 'Restock product ID belongs to another source product or branch.';
    end if;

    insert into public.inventory(branch_id, product_id, quantity, reorder_threshold, updated_at)
    values(v_branch_id, v_restock_id, v_qty, coalesce(v_restock_product.reorder_threshold, 5), now())
    on conflict(branch_id, product_id) do update
      set quantity = public.inventory.quantity + excluded.quantity, updated_at = now();
  end loop;

  if v_method = 'cash' and v_amount > 0 then
    perform public.post_pos_return_refund(v_id, v_refund_legs);
  elsif v_method = 'credit' and v_amount > 0 then
    if jsonb_array_length(v_refund_legs) <> 0 then
      raise exception using errcode = '22023', message = 'Credit returns cannot include cash refund legs.';
    end if;
    perform public.post_pos_credit_return(v_id);
  elsif jsonb_array_length(v_refund_legs) <> 0 then
    raise exception using errcode = '22023', message = 'Zero-value returns cannot include refund legs.';
  end if;

  update public.sale_returns set request_fingerprint = v_final_fingerprint where id = v_id;
  return jsonb_build_object('return_id', v_id, 'status', 'approved', 'duplicate', false);
end;
$function$;

revoke all on function public.commit_pos_return_v2(jsonb) from public, anon;
grant execute on function public.commit_pos_return_v2(jsonb) to authenticated;

commit;
