-- STAGING-ONLY DRAFT: do not run in production.
-- Additive secure customer buy-in boundary. Current direct writes remain intact.

begin;

create or replace function public.commit_customer_buyin_v2(p_buyin jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_purchase_id uuid := nullif(p_buyin->>'id', '')::uuid;
  v_branch_id uuid := nullif(p_buyin->>'branch_id', '')::uuid;
  v_product_id uuid := nullif(p_buyin->>'product_id', '')::uuid;
  v_unit_id uuid := nullif(p_buyin->>'inventory_unit_id', '')::uuid;
  v_account_id uuid := nullif(p_buyin->>'payment_account_id', '')::uuid;
  v_tenant_id uuid;
  v_product public.products%rowtype;
  v_account public.accounts%rowtype;
  v_existing public.customer_purchases%rowtype;
  v_account_transaction_id uuid := gen_random_uuid();
  v_quantity integer;
  v_price numeric := coalesce(nullif(p_buyin->>'purchase_price', '')::numeric, 0);
  v_sale_price numeric := coalesce(nullif(p_buyin->>'expected_sale_price', '')::numeric, 0);
  v_imei text := nullif(btrim(coalesce(p_buyin->>'imei1', '')), '');
  v_is_new_product boolean := coalesce((p_buyin->>'create_product')::boolean, false);
begin
  if jsonb_typeof(p_buyin) <> 'object' or v_purchase_id is null
     or v_branch_id is null or v_product_id is null or v_unit_id is null
     or v_imei is null or v_price < 0 or v_sale_price < 0
     or nullif(btrim(coalesce(p_buyin->>'seller_name', '')), '') is null
     or nullif(btrim(coalesce(p_buyin->>'seller_cnic', '')), '') is null
     or nullif(btrim(coalesce(p_buyin->>'seller_phone', '')), '') is null then
    raise exception using errcode = '22023', message = 'Buy-in payload is invalid.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_purchase_id::text, 0));
  select * into v_existing from public.customer_purchases where id = v_purchase_id;
  if found then
    if v_existing.branch_id = v_branch_id and v_existing.product_id = v_product_id
       and v_existing.imei1 = v_imei and v_existing.created_by = auth.uid() then
      select quantity into v_quantity from public.inventory
      where branch_id = v_branch_id and product_id = v_product_id;
      return jsonb_build_object('purchase_id', v_purchase_id, 'product_id', v_product_id,
        'inventory_unit_id', v_unit_id, 'quantity', v_quantity, 'duplicate', true);
    end if;
    raise exception using errcode = '23505', message = 'Buy-in id is already used with different contents.';
  end if;

  select tenant_id into v_tenant_id from public.branches where id = v_branch_id;
  if v_tenant_id is null then
    raise exception using errcode = '22023', message = 'Buy-in branch is invalid.';
  end if;
  if not public.current_user_has_branch_permission(v_tenant_id, v_branch_id, 'inventory.imei.manage') then
    raise exception using errcode = '42501', message = 'IMEI-management permission is required.';
  end if;

  select * into v_product from public.products where id = v_product_id for update;
  if found then
    if v_product.tenant_id <> v_tenant_id or v_product.branch_id <> v_branch_id
       or not public.current_user_has_branch_permission(v_tenant_id, v_branch_id, 'inventory.product.update') then
      raise exception using errcode = '42501', message = 'Product-update permission is required.';
    end if;
  else
    if not v_is_new_product or not public.current_user_has_branch_permission(
      v_tenant_id, v_branch_id, 'inventory.product.create'
    ) then
      raise exception using errcode = '42501', message = 'Product-create permission is required.';
    end if;
    insert into public.products (
      id, tenant_id, branch_id, category_id, name, sku, barcode, sale_price,
      cost_price, imei_tracked, is_active, description, updated_at
    ) values (
      v_product_id, v_tenant_id, v_branch_id,
      nullif(p_buyin->>'category_id', '')::uuid,
      nullif(btrim(p_buyin->>'product_name'), ''),
      nullif(btrim(p_buyin->>'sku'), ''), v_imei, v_sale_price, v_price,
      true, true, nullif(btrim(p_buyin->>'product_description'), ''), now()
    ) returning * into v_product;
  end if;

  -- The branch/IMEI unique constraint makes duplicate units impossible.
  if exists (select 1 from public.inventory_units where branch_id = v_branch_id and imei = v_imei) then
    raise exception using errcode = '23505', message = 'IMEI already exists in this branch.';
  end if;

  insert into public.inventory (branch_id, product_id, quantity, reorder_threshold, updated_at)
  values (v_branch_id, v_product_id, 1, coalesce(v_product.reorder_threshold, 5), now())
  on conflict (branch_id, product_id) do update
  set quantity = public.inventory.quantity + 1, updated_at = now()
  returning quantity into v_quantity;

  insert into public.inventory_units (id, tenant_id, branch_id, product_id, imei, status)
  values (v_unit_id, v_tenant_id, v_branch_id, v_product_id, v_imei, 'available');

  if v_account_id is not null and v_price > 0 then
    if not public.current_user_has_branch_permission(
      v_tenant_id, v_branch_id, 'account.transaction.create'
    ) then
      raise exception using errcode = '42501', message = 'Account-transaction permission is required.';
    end if;
    select * into v_account from public.accounts where id = v_account_id for update;
    if v_account.id is null or v_account.tenant_id <> v_tenant_id
       or v_account.branch_id <> v_branch_id or not v_account.is_active
       or v_account.current_balance < v_price then
      raise exception using errcode = '23514', message = 'Buy-in payment account is invalid or has insufficient balance.';
    end if;
    -- Use the existing idempotent ledger primitive so this transaction keeps
    -- its established source-event and audit guarantees.
    perform public.record_account_transaction_v2(
      v_account_transaction_id, v_tenant_id, v_branch_id, v_account_id,
      'purchase', 'out', v_price, 'Second-hand mobile buy-in',
      'customer_buyin', v_purchase_id::text,
      'customer_buyin:' || v_purchase_id::text, null, now()
    );
  end if;

  insert into public.customer_purchases (
    id, tenant_id, branch_id, seller_name, seller_cnic, seller_phone, seller_address,
    seller_photo_url, cnic_front_url, cnic_back_url, product_id, product_name, category_id,
    imei1, imei2, color, storage, device_condition, accessories, purchase_price,
    expected_sale_price, payment_account_id, payment_method, notes, declaration_agreed,
    status, created_by, created_at, updated_at
  ) values (
    v_purchase_id, v_tenant_id, v_branch_id, p_buyin->>'seller_name', p_buyin->>'seller_cnic',
    p_buyin->>'seller_phone', nullif(p_buyin->>'seller_address',''), nullif(p_buyin->>'seller_photo_url',''),
    nullif(p_buyin->>'cnic_front_url',''), nullif(p_buyin->>'cnic_back_url',''), v_product_id,
    coalesce(nullif(p_buyin->>'product_name',''), v_product.name), nullif(p_buyin->>'category_id','')::uuid,
    v_imei, nullif(p_buyin->>'imei2',''), nullif(p_buyin->>'color',''), nullif(p_buyin->>'storage',''),
    nullif(p_buyin->>'device_condition',''), nullif(p_buyin->>'accessories',''), v_price, v_sale_price,
    v_account_id, nullif(p_buyin->>'payment_method',''), nullif(p_buyin->>'notes',''),
    coalesce((p_buyin->>'declaration_agreed')::boolean, true), 'in_stock', auth.uid(), now(), now()
  );

  return jsonb_build_object('purchase_id', v_purchase_id, 'product_id', v_product_id,
    'inventory_unit_id', v_unit_id, 'quantity', v_quantity, 'duplicate', false);
end;
$function$;

revoke all on function public.commit_customer_buyin_v2(jsonb) from public, anon;
grant execute on function public.commit_customer_buyin_v2(jsonb) to authenticated;
commit;
