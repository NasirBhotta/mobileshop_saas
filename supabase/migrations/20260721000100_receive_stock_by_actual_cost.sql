-- Keep stock acquired at different unit costs as separate inventory products.
-- The original product remains the catalogue root; cost variants have no
-- barcode because a branch barcode must identify exactly one product.

alter table public.products
  add column if not exists source_product_id uuid
  references public.products(id) on delete set null;

create index if not exists products_cost_variant_lookup_idx
  on public.products (
    tenant_id,
    branch_id,
    source_product_id,
    cost_price
  );

create or replace function public.receive_purchase_order_goods(
  p_receipt_id uuid,
  p_receipt_no text,
  p_po_id uuid,
  p_note text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_po record;
  v_item record;
  v_po_item record;
  v_source_product public.products%rowtype;
  v_root_product_id uuid;
  v_inventory_product_id uuid;
  v_line_total numeric(12,2);
  v_total numeric(12,2) := 0;
  v_has_any_received boolean := false;
  v_all_received boolean := false;
begin
  select * into v_po
  from public.purchase_orders
  where id = p_po_id
  for update;

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
      purchase_order_item_id uuid,
      received_quantity integer,
      actual_unit_cost numeric,
      update_product_cost boolean
    )
  loop
    if coalesce(v_item.received_quantity, 0) <= 0 then continue; end if;
    if v_item.actual_unit_cost is null or v_item.actual_unit_cost < 0 then
      raise exception 'Actual unit cost must be zero or greater.';
    end if;

    select * into v_po_item
    from public.purchase_order_items
    where id = v_item.purchase_order_item_id
      and purchase_order_id = v_po.id
    for update;

    if not found then raise exception 'PO item not found.'; end if;
    if v_po_item.received_quantity + v_item.received_quantity >
       v_po_item.ordered_quantity then
      raise exception 'Received quantity cannot exceed ordered quantity.';
    end if;

    select * into v_source_product
    from public.products
    where id = v_po_item.product_id
      and tenant_id = v_po.tenant_id
      and branch_id = v_po.branch_id
    for update;

    if not found then raise exception 'Purchase order product not found.'; end if;

    v_root_product_id := coalesce(
      v_source_product.source_product_id,
      v_source_product.id
    );

    select p.id into v_inventory_product_id
    from public.products p
    where p.tenant_id = v_po.tenant_id
      and p.branch_id = v_po.branch_id
      and p.is_active
      and (p.id = v_root_product_id or p.source_product_id = v_root_product_id)
      and p.cost_price = v_item.actual_unit_cost
    order by case when p.id = v_root_product_id then 0 else 1 end, p.created_at
    limit 1
    for update;

    if v_inventory_product_id is null then
      v_inventory_product_id := gen_random_uuid();
      insert into public.products(
        id, tenant_id, branch_id, category_id, name, sku, barcode,
        description, sale_price, cost_price, imei_tracked, is_active,
        reorder_threshold, source_product_id
      ) values (
        v_inventory_product_id,
        v_source_product.tenant_id,
        v_source_product.branch_id,
        v_source_product.category_id,
        v_source_product.name,
        case
          when nullif(trim(v_source_product.sku), '') is null then null
          else v_source_product.sku || '-C' ||
               replace(v_item.actual_unit_cost::text, '.', '_')
        end,
        null,
        v_source_product.description,
        v_source_product.sale_price,
        v_item.actual_unit_cost,
        v_source_product.imei_tracked,
        v_source_product.is_active,
        v_source_product.reorder_threshold,
        v_root_product_id
      );
    end if;

    v_line_total := v_item.received_quantity * v_item.actual_unit_cost;
    v_total := v_total + v_line_total;

    insert into public.goods_receipt_items(
      tenant_id, goods_receipt_id, purchase_order_id, purchase_order_item_id,
      product_id, received_quantity, actual_unit_cost,
      update_product_cost, line_total
    ) values (
      v_po.tenant_id, p_receipt_id, v_po.id, v_po_item.id,
      v_inventory_product_id, v_item.received_quantity,
      v_item.actual_unit_cost, false, v_line_total
    );

    update public.purchase_order_items
    set received_quantity = received_quantity + v_item.received_quantity,
        actual_unit_cost = v_item.actual_unit_cost
    where id = v_po_item.id;

    insert into public.inventory(branch_id, product_id, quantity, updated_at)
    values (
      v_po.branch_id, v_inventory_product_id,
      v_item.received_quantity, now()
    )
    on conflict (branch_id, product_id)
    do update set
      quantity = public.inventory.quantity + excluded.quantity,
      updated_at = now();
  end loop;

  if v_total <= 0 then
    raise exception 'Received quantity must be greater than zero.';
  end if;

  update public.goods_receipts
  set total_received_value = v_total
  where id = p_receipt_id;

  update public.purchase_orders
  set total_received_cost = total_received_cost + v_total
  where id = v_po.id;

  select exists (
    select 1 from public.purchase_order_items
    where purchase_order_id = v_po.id and received_quantity > 0
  ) into v_has_any_received;

  select not exists (
    select 1 from public.purchase_order_items
    where purchase_order_id = v_po.id
      and received_quantity < ordered_quantity
  ) into v_all_received;

  update public.purchase_orders
  set status = case
    when v_all_received then 'received'
    when v_has_any_received then 'partially_received'
    else status
  end
  where id = v_po.id;

  update public.suppliers
  set outstanding_balance = outstanding_balance + v_total
  where id = v_po.supplier_id;

  return p_receipt_id;
end
$function$;

revoke all on function public.receive_purchase_order_goods(
  uuid, text, uuid, text, jsonb
) from public, anon;
grant execute on function public.receive_purchase_order_goods(
  uuid, text, uuid, text, jsonb
) to authenticated, service_role;
