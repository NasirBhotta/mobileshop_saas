-- Safe, auditable PO cancellation and supplier-return workflow.
create table if not exists public.purchase_order_reversals (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id),
  branch_id uuid not null references public.branches(id),
  purchase_order_id uuid not null unique references public.purchase_orders(id),
  supplier_id uuid not null references public.suppliers(id),
  resolution text not null check (
    resolution in ('unreceived_cancel','supplier_refund','supplier_credit')
  ),
  received_value numeric(12,2) not null default 0,
  payable_reversed numeric(12,2) not null default 0,
  recovered_amount numeric(12,2) not null default 0,
  recovery_account_id uuid references public.accounts(id),
  recovery_ledger_transaction_id uuid unique
    references public.account_transactions(id),
  reason text not null,
  reversed_by uuid not null references public.users(id),
  reversed_at timestamptz not null default now()
);

create table if not exists public.supplier_advances (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id),
  branch_id uuid not null references public.branches(id),
  supplier_id uuid not null references public.suppliers(id),
  purchase_order_reversal_id uuid not null unique
    references public.purchase_order_reversals(id),
  amount numeric(12,2) not null check (amount > 0),
  status text not null default 'open' check (status in ('open','applied','refunded')),
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now()
);

alter table public.purchase_order_reversals enable row level security;
alter table public.supplier_advances enable row level security;
create policy "branch users read po reversals"
on public.purchase_order_reversals for select to authenticated using (
  public.current_user_has_branch_permission(
    tenant_id, branch_id, 'procurement.purchase_orders'
  )
);
create policy "branch users read supplier advances"
on public.supplier_advances for select to authenticated using (
  public.current_user_has_branch_permission(
    tenant_id, branch_id, 'supplier.supplier.view'
  )
);

create or replace function public.reverse_purchase_order_v1(
  p_po_id uuid,
  p_reversal_id uuid,
  p_resolution text,
  p_reason text,
  p_recovery_account_id uuid default null,
  p_recovery_ledger_transaction_id uuid default null
) returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_po public.purchase_orders%rowtype;
  v_supplier public.suppliers%rowtype;
  v_account public.accounts%rowtype;
  v_existing public.purchase_order_reversals%rowtype;
  v_item record;
  v_received numeric(12,2);
  v_payable numeric(12,2);
  v_recovered numeric(12,2);
begin
  if p_reversal_id is null or nullif(trim(p_reason),'') is null then
    raise exception using errcode='22023',
      message='A cancellation/return reason is required.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_po_id::text,0));
  select * into v_po from public.purchase_orders
  where id=p_po_id for update;
  if not found then raise exception 'Purchase order not found.'; end if;
  if public.current_user_tenant_id() <> v_po.tenant_id then
    raise exception using errcode='42501', message='Not allowed.';
  end if;

  select * into v_existing from public.purchase_order_reversals
  where purchase_order_id=p_po_id;
  if v_existing.id is not null then
    if v_existing.id is distinct from p_reversal_id
       or v_existing.resolution is distinct from p_resolution then
      raise exception using errcode='23505',
        message='Purchase order was already reversed.';
    end if;
    return jsonb_build_object(
      'received_value',v_existing.received_value,
      'payable_reversed',v_existing.payable_reversed,
      'recovered_amount',v_existing.recovered_amount
    );
  end if;
  if v_po.status='cancelled' then
    raise exception 'Purchase order is already cancelled.';
  end if;

  select coalesce(sum(total_received_value),0) into v_received
  from public.goods_receipts where purchase_order_id=p_po_id;
  if v_received=0 then
    if p_resolution <> 'unreceived_cancel' then
      raise exception 'Unreceived PO must use simple cancellation.';
    end if;
    insert into public.purchase_order_reversals(
      id,tenant_id,branch_id,purchase_order_id,supplier_id,resolution,
      reason,reversed_by
    ) values (
      p_reversal_id,v_po.tenant_id,v_po.branch_id,v_po.id,v_po.supplier_id,
      p_resolution,trim(p_reason),auth.uid()
    );
    update public.purchase_orders set status='cancelled',updated_at=now()
    where id=p_po_id;
    return jsonb_build_object(
      'received_value',0,'payable_reversed',0,'recovered_amount',0
    );
  end if;
  if p_resolution not in ('supplier_refund','supplier_credit') then
    raise exception 'Received PO requires supplier return resolution.';
  end if;

  -- Lock and validate every inventory leg before changing anything.
  for v_item in
    select gri.product_id,sum(gri.received_quantity)::integer quantity,
      bool_or(gri.item_resolution='create_on_receipt') created_on_receipt
    from public.goods_receipt_items gri
    where gri.purchase_order_id=p_po_id and gri.product_id is not null
    group by gri.product_id
  loop
    perform 1 from public.inventory i
    where i.branch_id=v_po.branch_id and i.product_id=v_item.product_id
      and i.quantity >= v_item.quantity for update;
    if not found then
      raise exception using errcode='23514',
        message='Received stock has been sold, transferred, or consumed.';
    end if;
  end loop;

  select * into v_supplier from public.suppliers
  where id=v_po.supplier_id for update;
  v_payable := least(v_received,greatest(0,v_supplier.outstanding_balance));
  v_recovered := v_received-v_payable;

  if v_recovered>0 and p_resolution='supplier_refund' then
    if p_recovery_account_id is null
       or p_recovery_ledger_transaction_id is null then
      raise exception 'Select the account that received the supplier refund.';
    end if;
    select * into v_account from public.accounts
    where id=p_recovery_account_id for update;
    if v_account.id is null or not v_account.is_active
       or v_account.tenant_id<>v_po.tenant_id
       or v_account.branch_id<>v_po.branch_id then
      raise exception 'Supplier refund account is invalid.';
    end if;
  end if;

  insert into public.purchase_order_reversals(
    id,tenant_id,branch_id,purchase_order_id,supplier_id,resolution,
    received_value,payable_reversed,recovered_amount,recovery_account_id,
    recovery_ledger_transaction_id,reason,reversed_by
  ) values (
    p_reversal_id,v_po.tenant_id,v_po.branch_id,v_po.id,v_po.supplier_id,
    p_resolution,v_received,v_payable,v_recovered,
    case when p_resolution='supplier_refund' then p_recovery_account_id end,
    case when p_resolution='supplier_refund'
      then p_recovery_ledger_transaction_id end,
    trim(p_reason),auth.uid()
  );

  for v_item in
    select gri.product_id,sum(gri.received_quantity)::integer quantity,
      bool_or(gri.item_resolution='create_on_receipt') created_on_receipt
    from public.goods_receipt_items gri
    where gri.purchase_order_id=p_po_id and gri.product_id is not null
    group by gri.product_id
  loop
    update public.inventory set quantity=quantity-v_item.quantity,
      updated_at=now()
    where branch_id=v_po.branch_id and product_id=v_item.product_id;
    if v_item.created_on_receipt and not exists(
      select 1 from public.inventory i
      where i.product_id=v_item.product_id and i.quantity>0
    ) then
      update public.products set is_active=false,updated_at=now()
      where id=v_item.product_id;
    end if;
  end loop;

  update public.suppliers set outstanding_balance=
    greatest(0,outstanding_balance-v_payable),updated_at=now()
  where id=v_po.supplier_id;
  insert into public.supplier_ledger_entries(
    tenant_id,branch_id,supplier_id,entry_type,direction,amount,
    source_event_key,reference_type,reference_id,description,
    occurred_at,created_by
  ) values (
    v_po.tenant_id,v_po.branch_id,v_po.supplier_id,'purchase_return',
    'decrease',v_received,'supplier:po-reversal:'||p_reversal_id::text,
    'purchase_order',v_po.id,'Purchase order returned to supplier',
    now(),auth.uid()
  );

  if v_recovered>0 and p_resolution='supplier_refund' then
    insert into public.account_transactions(
      id,tenant_id,branch_id,account_id,transaction_type,direction,amount,
      description,reference_type,reference_id,source_event_key,
      transaction_at,created_by,created_at
    ) values (
      p_recovery_ledger_transaction_id,v_po.tenant_id,v_po.branch_id,
      p_recovery_account_id,'other','in',v_recovered,'Supplier return refund',
      'purchase_order_reversal',p_reversal_id::text,
      'supplier:po-refund:'||p_reversal_id::text,now(),auth.uid(),now()
    );
    update public.accounts set current_balance=current_balance+v_recovered,
      updated_at=now() where id=p_recovery_account_id;
  elsif v_recovered>0 then
    insert into public.supplier_advances(
      id,tenant_id,branch_id,supplier_id,purchase_order_reversal_id,
      amount,created_by
    ) values (
      gen_random_uuid(),v_po.tenant_id,v_po.branch_id,v_po.supplier_id,
      p_reversal_id,v_recovered,auth.uid()
    );
  end if;
  update public.purchase_orders set status='cancelled',updated_at=now()
  where id=p_po_id;
  return jsonb_build_object(
    'received_value',v_received,'payable_reversed',v_payable,
    'recovered_amount',v_recovered
  );
end
$function$;

revoke all on function public.reverse_purchase_order_v1(
  uuid,uuid,text,text,uuid,uuid
) from public,anon;
grant execute on function public.reverse_purchase_order_v1(
  uuid,uuid,text,text,uuid,uuid
) to authenticated,service_role;
