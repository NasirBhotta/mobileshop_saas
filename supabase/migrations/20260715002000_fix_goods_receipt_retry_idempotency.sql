-- A timed-out receive request may already have committed on the server. A retry
-- with the same receipt ID must succeed before the now-received PO is rejected.
-- Keep this as a separate migration so environments that already applied the
-- procurement foundation receive the fix as well.

do $$
declare
  v_definition text;
  v_old text := $fragment$
  if v_po.status = 'received' then
    raise exception 'PO is already fully received.';
  end if;

  if exists (select 1 from public.goods_receipts where id = p_receipt_id) then
    return p_receipt_id;
  end if;
$fragment$;
  v_new text := $fragment$
  if exists (select 1 from public.goods_receipts where id = p_receipt_id) then
    return p_receipt_id;
  end if;

  if v_po.status = 'received' then
    raise exception 'PO is already fully received.';
  end if;
$fragment$;
begin
  select pg_get_functiondef(
    'public.receive_purchase_order_goods(uuid,text,uuid,text,jsonb)'::regprocedure
  )
  into v_definition;

  if position(v_new in v_definition) > 0 then
    return;
  end if;

  if position(v_old in v_definition) = 0 then
    raise exception
      'Could not patch receive_purchase_order_goods: expected status/idempotency checks were not found.';
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$$;
