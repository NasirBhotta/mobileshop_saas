-- STAGING-ONLY DRAFT: do not run in production.
-- Additive SEC-17 return-parent recovery boundary. Existing direct restore
-- remains untouched until client and staging compatibility evidence is complete.

begin;

create or replace function public.restore_pos_sale_for_return(p_sale jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_sale_id uuid := nullif(p_sale->>'id', '')::uuid;
  v_branch_id uuid := nullif(p_sale->>'branch_id', '')::uuid;
  v_sale_user_id uuid := nullif(p_sale->>'user_id', '')::uuid;
  v_tenant_id uuid;
begin
  if jsonb_typeof(p_sale) <> 'object'
     or v_sale_id is null
     or v_branch_id is null
     or v_sale_user_id is null
     or jsonb_typeof(p_sale->'sale_items') <> 'array'
     or jsonb_array_length(p_sale->'sale_items') = 0
     or jsonb_typeof(p_sale->'sale_payments') <> 'array'
     or jsonb_array_length(p_sale->'sale_payments') = 0 then
    raise exception using errcode = '22023',
      message = 'Sale-recovery payload is incomplete.';
  end if;

  select b.tenant_id into v_tenant_id from public.branches b where b.id = v_branch_id;
  if v_tenant_id is null
     or not public.current_user_has_branch_permission(
       v_tenant_id, v_branch_id, 'pos.sale.return'
     ) then
    raise exception using errcode = '42501',
      message = 'POS return permission is required for sale recovery.';
  end if;

  -- A recovered sale uses the same checkout validation, stock locking and
  -- payment/ledger logic as normal POS checkout. It cannot overwrite an
  -- existing parent or replace its children/payments.
  perform pg_advisory_xact_lock(hashtextextended(v_sale_id::text, 0));
  if exists (select 1 from public.sales s where s.id = v_sale_id) then
    raise exception using errcode = '23505',
      message = 'Sale parent already exists; reconcile incomplete children instead.';
  end if;
  if v_sale_user_id <> auth.uid() then
    raise exception using errcode = '42501',
      message = 'Only the original sale actor can recover this local parent.';
  end if;

  return public.commit_pos_sale_v2(p_sale);
end;
$function$;

revoke all on function public.restore_pos_sale_for_return(jsonb) from public, anon;
grant execute on function public.restore_pos_sale_for_return(jsonb) to authenticated;

commit;

-- No direct table revoke/policy change is included in this additive draft.
