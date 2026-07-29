-- create_purchase_order previously dereferenced an unassigned generic product
-- record for create_on_receipt items. Typed scalar values are reset per item.
create or replace function public.create_purchase_order(
  p_po_id uuid, p_po_no text, p_tenant_id uuid, p_branch_id uuid,
  p_supplier_id uuid, p_expected_delivery_at timestamptz, p_notes text,
  p_items jsonb
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_item record;
  v_existing_product_name text;
  v_existing_product_sku text;
  v_resolution text;
  v_name text;
  v_total numeric(12,2) := 0;
begin
  if not public.tenant_procurement_enabled(p_tenant_id) then
    raise exception 'Supplier & Procurement module is not enabled.';
  end if;
  if public.current_user_tenant_id() <> p_tenant_id then
    raise exception 'Not allowed.';
  end if;
  if exists (select 1 from public.purchase_orders where id = p_po_id) then
    return p_po_id;
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Purchase order must have at least one item.';
  end if;

  insert into public.purchase_orders(
    id, tenant_id, branch_id, supplier_id, po_no, status,
    expected_delivery_at, notes, total_expected_cost, created_by
  ) values (
    p_po_id, p_tenant_id, p_branch_id, p_supplier_id, p_po_no, 'draft',
    p_expected_delivery_at, p_notes, 0, auth.uid()
  );

  for v_item in
    select * from jsonb_to_recordset(p_items) as x(
      id uuid, product_id uuid, product_resolution text, product_draft jsonb,
      resolved_product_id uuid, product_name text, product_sku text,
      ordered_quantity integer, negotiated_unit_cost numeric
    )
  loop
    v_existing_product_name := null;
    v_existing_product_sku := null;
    v_resolution := coalesce(v_item.product_resolution, 'existing_product');
    if v_resolution not in (
      'existing_product', 'create_on_receipt',
      'resolve_on_receipt', 'direct_use'
    ) then raise exception 'Invalid product resolution.'; end if;
    if coalesce(v_item.ordered_quantity, 0) <= 0 then
      raise exception 'Ordered quantity must be greater than zero.';
    end if;
    if v_item.negotiated_unit_cost is null
       or v_item.negotiated_unit_cost < 0 then
      raise exception 'Unit cost cannot be negative.';
    end if;

    if v_resolution = 'existing_product' then
      select name, sku
      into v_existing_product_name, v_existing_product_sku
      from public.products
      where id = v_item.product_id and tenant_id = p_tenant_id
        and branch_id = p_branch_id and is_active
      limit 1;
      if not found then
        raise exception 'Product does not exist in catalog.';
      end if;
      v_name := v_existing_product_name;
    else
      v_name := nullif(trim(v_item.product_name), '');
      if v_name is null then raise exception 'Item name is required.'; end if;
      if v_resolution = 'create_on_receipt' then
        if v_item.resolved_product_id is null then
          raise exception 'New product identity is required.';
        end if;
        if nullif(trim(v_item.product_draft->>'name'), '') is null then
          raise exception 'New product details are required.';
        end if;
      end if;
    end if;

    insert into public.purchase_order_items(
      id, tenant_id, purchase_order_id, product_id, product_resolution,
      product_draft, resolved_product_id, product_name, product_sku,
      ordered_quantity, negotiated_unit_cost, line_total
    ) values (
      coalesce(v_item.id, gen_random_uuid()), p_tenant_id, p_po_id,
      v_item.product_id, v_resolution, v_item.product_draft,
      v_item.resolved_product_id, coalesce(v_name, v_item.product_name),
      case when v_resolution = 'existing_product'
        then coalesce(v_item.product_sku, v_existing_product_sku)
        else v_item.product_sku end,
      v_item.ordered_quantity, v_item.negotiated_unit_cost,
      v_item.ordered_quantity * v_item.negotiated_unit_cost
    );

    if v_item.product_id is not null then
      insert into public.supplier_products(
        tenant_id, supplier_id, product_id, last_cost
      ) values (
        p_tenant_id, p_supplier_id, v_item.product_id,
        v_item.negotiated_unit_cost
      ) on conflict (supplier_id, product_id)
      do update set last_cost = excluded.last_cost;
    end if;
    v_total := v_total +
      (v_item.ordered_quantity * v_item.negotiated_unit_cost);
  end loop;

  update public.purchase_orders set total_expected_cost = v_total
  where id = p_po_id;
  return p_po_id;
end
$function$;

revoke all on function public.create_purchase_order(
  uuid,text,uuid,uuid,uuid,timestamptz,text,jsonb
) from public, anon;
grant execute on function public.create_purchase_order(
  uuid,text,uuid,uuid,uuid,timestamptz,text,jsonb
) to authenticated, service_role;
