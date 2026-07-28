-- Execute explicit PO item resolution without changing money accounts.

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
  v_product record;
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
    v_resolution := coalesce(v_item.product_resolution, 'existing_product');
    if v_resolution not in (
      'existing_product', 'create_on_receipt',
      'resolve_on_receipt', 'direct_use'
    ) then raise exception 'Invalid product resolution.'; end if;
    if coalesce(v_item.ordered_quantity, 0) <= 0 then
      raise exception 'Ordered quantity must be greater than zero.';
    end if;
    if v_item.negotiated_unit_cost is null or
       v_item.negotiated_unit_cost < 0 then
      raise exception 'Unit cost cannot be negative.';
    end if;

    if v_resolution = 'existing_product' then
      select id, name, sku into v_product
      from public.products
      where id = v_item.product_id and tenant_id = p_tenant_id
        and branch_id = p_branch_id and is_active
      limit 1;
      if not found then raise exception 'Product does not exist in catalog.'; end if;
      v_name := v_product.name;
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
        then coalesce(v_item.product_sku, v_product.sku)
        else v_item.product_sku end,
      v_item.ordered_quantity,
      v_item.negotiated_unit_cost,
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

create or replace function public.receive_purchase_order_goods(
  p_receipt_id uuid, p_receipt_no text, p_po_id uuid, p_note text,
  p_items jsonb
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_po record;
  v_item record;
  v_po_item record;
  v_source_product public.products%rowtype;
  v_resolution text;
  v_inventory_product_id uuid;
  v_root_product_id uuid;
  v_line_total numeric(12,2);
  v_total numeric(12,2) := 0;
  v_has_any_received boolean;
  v_all_received boolean;
begin
  select * into v_po from public.purchase_orders
  where id = p_po_id for update;
  if not found then raise exception 'Purchase order not found.'; end if;
  if public.current_user_tenant_id() <> v_po.tenant_id then
    raise exception 'Not allowed.';
  end if;
  if v_po.status = 'cancelled' then
    raise exception 'Cannot receive goods against cancelled PO.';
  end if;
  if exists (select 1 from public.goods_receipts where id = p_receipt_id) then
    return p_receipt_id;
  end if;
  if v_po.status = 'received' then
    raise exception 'PO is already fully received.';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No received items provided.';
  end if;

  insert into public.goods_receipts(
    id, tenant_id, branch_id, purchase_order_id, supplier_id,
    receipt_no, note, received_by, total_received_value
  ) values (
    p_receipt_id, v_po.tenant_id, v_po.branch_id, v_po.id,
    v_po.supplier_id, p_receipt_no, p_note, auth.uid(), 0
  );

  for v_item in
    select * from jsonb_to_recordset(p_items) as x(
      purchase_order_item_id uuid, received_quantity integer,
      actual_unit_cost numeric, update_product_cost boolean,
      resolved_product_id uuid, product_draft jsonb
    )
  loop
    if coalesce(v_item.received_quantity, 0) <= 0 then continue; end if;
    if v_item.actual_unit_cost is null or v_item.actual_unit_cost < 0 then
      raise exception 'Actual unit cost must be zero or greater.';
    end if;
    select * into v_po_item from public.purchase_order_items
    where id = v_item.purchase_order_item_id
      and purchase_order_id = v_po.id for update;
    if not found then raise exception 'PO item not found.'; end if;
    if v_po_item.received_quantity + v_item.received_quantity >
       v_po_item.ordered_quantity then
      raise exception 'Received quantity cannot exceed ordered quantity.';
    end if;

    v_resolution := coalesce(
      v_po_item.product_resolution, 'existing_product'
    );
    v_inventory_product_id := null;

    if v_resolution = 'direct_use' then
      null;
    elsif v_resolution = 'create_on_receipt' then
      v_inventory_product_id := v_po_item.resolved_product_id;
      if v_inventory_product_id is null then
        raise exception 'New product identity is missing.';
      end if;
      insert into public.products(
        id, tenant_id, branch_id, name, sku, sale_price, cost_price,
        imei_tracked, is_active
      ) values (
        v_inventory_product_id, v_po.tenant_id, v_po.branch_id,
        v_po_item.product_draft->>'name',
        nullif(trim(v_po_item.product_draft->>'sku'), ''),
        coalesce((v_po_item.product_draft->>'sale_price')::numeric, 0),
        v_item.actual_unit_cost, false, true
      ) on conflict (id) do nothing;
    else
      v_inventory_product_id := case
        when v_resolution = 'existing_product' then v_po_item.product_id
        else v_item.resolved_product_id
      end;
      if v_inventory_product_id is null then
        raise exception 'Choose an inventory product before receipt.';
      end if;
      select * into v_source_product from public.products
      where id = v_inventory_product_id and tenant_id = v_po.tenant_id
        and branch_id = v_po.branch_id and is_active for update;
      if not found then raise exception 'Resolved product not found.'; end if;
      v_root_product_id := coalesce(
        v_source_product.source_product_id, v_source_product.id
      );
      select p.id into v_inventory_product_id from public.products p
      where p.tenant_id = v_po.tenant_id and p.branch_id = v_po.branch_id
        and p.is_active
        and (p.id = v_root_product_id or p.source_product_id = v_root_product_id)
        and p.cost_price = v_item.actual_unit_cost
      order by case when p.id = v_root_product_id then 0 else 1 end, p.created_at
      limit 1 for update;
      if v_inventory_product_id is null then
        v_inventory_product_id := gen_random_uuid();
        insert into public.products(
          id, tenant_id, branch_id, category_id, name, sku, barcode,
          description, sale_price, cost_price, imei_tracked, is_active,
          reorder_threshold, source_product_id
        ) values (
          v_inventory_product_id, v_source_product.tenant_id,
          v_source_product.branch_id, v_source_product.category_id,
          v_source_product.name,
          case when nullif(trim(v_source_product.sku), '') is null then null
            else v_source_product.sku || '-C' ||
              replace(v_item.actual_unit_cost::text, '.', '_') end,
          null, v_source_product.description, v_source_product.sale_price,
          v_item.actual_unit_cost, v_source_product.imei_tracked,
          v_source_product.is_active, v_source_product.reorder_threshold,
          v_root_product_id
        );
      end if;
    end if;

    v_line_total := v_item.received_quantity * v_item.actual_unit_cost;
    v_total := v_total + v_line_total;
    insert into public.goods_receipt_items(
      tenant_id, goods_receipt_id, purchase_order_id, purchase_order_item_id,
      product_id, item_resolution, item_name, received_quantity,
      actual_unit_cost, update_product_cost, line_total
    ) values (
      v_po.tenant_id, p_receipt_id, v_po.id, v_po_item.id,
      v_inventory_product_id, v_resolution, v_po_item.product_name,
      v_item.received_quantity, v_item.actual_unit_cost, false, v_line_total
    );
    update public.purchase_order_items
    set received_quantity = received_quantity + v_item.received_quantity,
        actual_unit_cost = v_item.actual_unit_cost,
        resolved_product_id = coalesce(
          resolved_product_id, v_inventory_product_id
        )
    where id = v_po_item.id;

    if v_inventory_product_id is not null then
      insert into public.inventory(branch_id, product_id, quantity, updated_at)
      values (
        v_po.branch_id, v_inventory_product_id,
        v_item.received_quantity, now()
      ) on conflict (branch_id, product_id) do update set
        quantity = public.inventory.quantity + excluded.quantity,
        updated_at = now();
      insert into public.supplier_products(
        tenant_id, supplier_id, product_id, last_cost
      ) values (
        v_po.tenant_id, v_po.supplier_id, v_inventory_product_id,
        v_item.actual_unit_cost
      ) on conflict (supplier_id, product_id)
      do update set last_cost = excluded.last_cost;
    end if;
  end loop;

  if v_total <= 0 then
    raise exception 'Received quantity must be greater than zero.';
  end if;
  update public.goods_receipts set total_received_value = v_total
  where id = p_receipt_id;
  update public.purchase_orders
  set total_received_cost = total_received_cost + v_total where id = v_po.id;
  select exists (
    select 1 from public.purchase_order_items
    where purchase_order_id = v_po.id and received_quantity > 0
  ) into v_has_any_received;
  select not exists (
    select 1 from public.purchase_order_items
    where purchase_order_id = v_po.id
      and received_quantity < ordered_quantity
  ) into v_all_received;
  update public.purchase_orders set status = case
    when v_all_received then 'received'
    when v_has_any_received then 'partially_received'
    else status end
  where id = v_po.id;
  update public.suppliers
  set outstanding_balance = outstanding_balance + v_total
  where id = v_po.supplier_id;
  return p_receipt_id;
end
$function$;

revoke all on function public.create_purchase_order(
  uuid, text, uuid, uuid, uuid, timestamptz, text, jsonb
) from public, anon;
grant execute on function public.create_purchase_order(
  uuid, text, uuid, uuid, uuid, timestamptz, text, jsonb
) to authenticated, service_role;
revoke all on function public.receive_purchase_order_goods(
  uuid, text, uuid, text, jsonb
) from public, anon;
grant execute on function public.receive_purchase_order_goods(
  uuid, text, uuid, text, jsonb
) to authenticated, service_role;
