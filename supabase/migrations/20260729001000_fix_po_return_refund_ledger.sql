-- A PO refund reversal reserves its recovery ledger id before the account
-- transaction is inserted. Defer the FK until the atomic RPC finishes.

alter table public.purchase_order_reversals
  alter constraint purchase_order_reversals_recovery_ledger_transaction_id_fkey
  deferrable initially deferred;

create or replace function public.reverse_purchase_order_v2(
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
  v_result jsonb;
begin
  v_result := public.reverse_purchase_order_v1(
    p_po_id,
    p_reversal_id,
    p_resolution,
    p_reason,
    p_recovery_account_id,
    p_recovery_ledger_transaction_id
  );

  -- When no earlier supplier payment exists there is no money to recover and
  -- therefore no account transaction. Do not retain a phantom ledger link.
  if coalesce((v_result->>'recovered_amount')::numeric, 0) = 0 then
    update public.purchase_order_reversals
    set recovery_account_id = null,
        recovery_ledger_transaction_id = null
    where id = p_reversal_id;
  end if;

  return v_result;
end
$function$;

revoke all on function public.reverse_purchase_order_v2(
  uuid,uuid,text,text,uuid,uuid
) from public, anon;
grant execute on function public.reverse_purchase_order_v2(
  uuid,uuid,text,text,uuid,uuid
) to authenticated, service_role;
