-- STAGING-ONLY DRAFT: do not run in production.
-- Additive SEC-17 product-sync boundary. It does not revoke current direct
-- table access, replace policies, or change an existing server function.

begin;

create or replace function public.upsert_inventory_product_v2(p_product jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_product_id uuid := nullif(p_product->>'id', '')::uuid;
  v_branch_id uuid := nullif(p_product->>'branch_id', '')::uuid;
  v_category_id uuid := nullif(p_product->>'category_id', '')::uuid;
  v_name text := nullif(btrim(coalesce(p_product->>'name', '')), '');
  v_sku text := nullif(btrim(coalesce(p_product->>'sku', '')), '');
  v_barcode text := nullif(btrim(coalesce(p_product->>'barcode', '')), '');
  v_description text := nullif(btrim(coalesce(p_product->>'description', '')), '');
  v_sale_price numeric := coalesce(nullif(p_product->>'sale_price', '')::numeric, 0);
  v_cost_price numeric := coalesce(nullif(p_product->>'cost_price', '')::numeric, 0);
  v_imei_tracked boolean := coalesce((p_product->>'imei_tracked')::boolean, false);
  v_is_active boolean := coalesce((p_product->>'is_active')::boolean, true);
  v_reorder_threshold integer := greatest(
    coalesce(nullif(p_product->>'reorder_threshold', '')::integer, 5), 0
  );
  v_initial_stock integer := greatest(
    coalesce(nullif(p_product->>'stock', '')::integer, 0), 0
  );
  v_tenant_id uuid;
  v_existing public.products%rowtype;
  v_created boolean := false;
begin
  if jsonb_typeof(p_product) <> 'object'
     or v_product_id is null
     or v_branch_id is null
     or v_name is null
     or v_sale_price < 0
     or v_cost_price < 0 then
    raise exception using errcode = '22023',
      message = 'Product payload is invalid.';
  end if;

  select b.tenant_id into v_tenant_id
  from public.branches b where b.id = v_branch_id;
  if v_tenant_id is null then
    raise exception using errcode = '22023', message = 'Product branch is invalid.';
  end if;

  select * into v_existing from public.products p
  where p.id = v_product_id for update;

  if found then
    if v_existing.tenant_id <> v_tenant_id or v_existing.branch_id <> v_branch_id then
      raise exception using errcode = '42501',
        message = 'Product belongs to another tenant or branch.';
    end if;
    if not public.current_user_has_branch_permission(
      v_tenant_id, v_branch_id,
      case when not v_is_active then 'inventory.product.delete'
           else 'inventory.product.update' end
    ) then
      raise exception using errcode = '42501', message = 'Product permission is required.';
    end if;

    -- Deliberately do not update quantity here. Cached product snapshots carry
    -- a stock value, but only the stock-adjustment operation may change stock.
    update public.products
    set category_id = v_category_id, name = v_name, sku = v_sku,
        barcode = v_barcode, description = v_description,
        sale_price = v_sale_price, cost_price = v_cost_price,
        imei_tracked = v_imei_tracked, is_active = v_is_active,
        reorder_threshold = v_reorder_threshold, updated_at = now()
    where id = v_product_id;

    insert into public.inventory (
      branch_id, product_id, quantity, reorder_threshold, updated_at
    ) values (v_branch_id, v_product_id, 0, v_reorder_threshold, now())
    on conflict (branch_id, product_id) do update
      set reorder_threshold = excluded.reorder_threshold, updated_at = now();
  else
    if not public.current_user_has_branch_permission(
      v_tenant_id, v_branch_id, 'inventory.product.create'
    ) then
      raise exception using errcode = '42501', message = 'Product-create permission is required.';
    end if;

    insert into public.products (
      id, tenant_id, branch_id, category_id, name, sku, barcode, description,
      sale_price, cost_price, imei_tracked, is_active, reorder_threshold, updated_at
    ) values (
      v_product_id, v_tenant_id, v_branch_id, v_category_id, v_name, v_sku,
      v_barcode, v_description, v_sale_price, v_cost_price, v_imei_tracked,
      v_is_active, v_reorder_threshold, now()
    );
    insert into public.inventory (
      branch_id, product_id, quantity, reorder_threshold, updated_at
    ) values (
      v_branch_id, v_product_id, v_initial_stock, v_reorder_threshold, now()
    );
    v_created := true;
  end if;

  return jsonb_build_object('product_id', v_product_id, 'created', v_created);
end;
$function$;

revoke all on function public.upsert_inventory_product_v2(jsonb) from public, anon;
grant execute on function public.upsert_inventory_product_v2(jsonb) to authenticated;

commit;

-- Intentionally absent: direct product/inventory revokes and RLS changes.
