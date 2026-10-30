-- Additive rollout: preserve legacy v2 RPC semantics and every historical posting.
begin;
alter table public.repair_tickets
  add column if not exists delivery_accounting boolean not null default false;
create or replace function public.prepare_repair_ticket_v3(
  p_ticket_id uuid, p_event_id uuid, p_customer_charge numeric,
  p_service_charge numeric default 0, p_discount numeric default 0,
  p_commission numeric default 0, p_other_direct_cost numeric default 0
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_ticket public.repair_tickets%rowtype;
  v_part record;
  v_inventory_cost numeric(12,2) := 0;
  v_direct_cost numeric(12,2) := 0;
  v_profit numeric(12,2);
  v_paid numeric(12,2);
begin
  select * into v_ticket from public.repair_tickets
  where id = p_ticket_id for update;
  if not found then raise exception 'Repair ticket not found.'; end if;
  if public.current_user_tenant_id() is distinct from v_ticket.tenant_id then
    raise exception 'Not allowed.';
  end if;
  if public.current_user_has_branch_permission(
    v_ticket.tenant_id, v_ticket.branch_id, 'repair.ticket.update'
  ) is not true then raise exception 'Not allowed.'; end if;
  if v_ticket.status in ('completed','delivered','cancelled') and v_ticket.delivery_accounting
    and v_ticket.customer_charge is not distinct from p_customer_charge
    and v_ticket.service_charge = coalesce(p_service_charge,0)
    and v_ticket.discount_amount = coalesce(p_discount,0)
    and v_ticket.per_job_commission = coalesce(p_commission,0)
    and v_ticket.other_direct_cost = coalesce(p_other_direct_cost,0)
  then return p_event_id; end if;
  if v_ticket.status in ('completed','delivered','cancelled') then
    raise exception 'Ticket cannot be completed from its current status.';
  end if;
  if p_customer_charge is null or p_customer_charge < 0 or
     coalesce(p_service_charge,0) < 0 or coalesce(p_discount,0) < 0 or
     coalesce(p_commission,0) < 0 or coalesce(p_other_direct_cost,0) < 0 then
    raise exception 'Repair financial amounts cannot be negative.';
  end if;

  select coalesce(sum(amount),0) into v_paid
  from public.repair_payments where ticket_id = p_ticket_id;
  if v_paid > p_customer_charge + 0.01 then
    raise exception 'Customer charge cannot be below payments already received.';
  end if;
  update public.repair_tickets set status = 'completed',
    customer_charge = p_customer_charge, total_cost = p_customer_charge,
    service_charge = coalesce(p_service_charge,0),
    discount_amount = coalesce(p_discount,0),
    delivery_accounting = true,
    labor_cost = coalesce(p_commission,0),
    per_job_commission = coalesce(p_commission,0),
    other_direct_cost = coalesce(p_other_direct_cost,0),
    completed_at = now(), updated_at = now()
  where id = p_ticket_id;
  insert into public.repair_status_logs(
    ticket_id, tenant_id, branch_id, old_status, new_status,
    changed_by, note
  ) values (
    p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, v_ticket.status,
    'completed', auth.uid(), 'Repair financial completion'
  );
  return p_event_id;
end
$function$;

create or replace function public.deliver_repair_ticket_v3(
  p_ticket_id uuid, p_event_id uuid
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_ticket public.repair_tickets%rowtype;
  p_customer_charge numeric; p_service_charge numeric; p_discount numeric;
  p_commission numeric; p_other_direct_cost numeric;
  v_part record;
  v_inventory_cost numeric(12,2) := 0;
  v_direct_cost numeric(12,2) := 0;
  v_profit numeric(12,2);
  v_paid numeric(12,2);
begin
  select * into v_ticket from public.repair_tickets
  where id = p_ticket_id for update;
  if not found then raise exception 'Repair ticket not found.'; end if;
  if public.current_user_tenant_id() is distinct from v_ticket.tenant_id then
    raise exception 'Not allowed.';
  end if;
  if public.current_user_has_branch_permission(
    v_ticket.tenant_id, v_ticket.branch_id, 'repair.ticket.update'
  ) is not true then raise exception 'Not allowed.'; end if;
  if exists(select 1 from public.repair_status_logs where id = p_event_id
    and ticket_id = p_ticket_id and new_status = 'delivered') then return p_event_id; end if;
  if v_ticket.status = 'delivered' then return p_event_id; end if;
  if v_ticket.status <> 'completed' then
    raise exception 'Only completed tickets may be delivered.';
  end if;
  -- Historical completion postings are immutable: only hand over the device.
  if not v_ticket.delivery_accounting or v_ticket.finalized_at is not null or exists (
    select 1 from public.repair_financial_events
    where ticket_id = p_ticket_id and event_type = 'completion'
  ) then
    update public.repair_tickets set status = 'delivered', delivered_at = now(), updated_at = now()
    where id = p_ticket_id;
    insert into public.repair_status_logs(id,ticket_id, tenant_id, branch_id, old_status, new_status, changed_by)
    values(p_event_id,p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, 'completed', 'delivered', auth.uid());
    return p_event_id;
  end if;
  p_customer_charge := v_ticket.customer_charge;
  p_service_charge := v_ticket.service_charge; p_discount := v_ticket.discount_amount;
  p_commission := v_ticket.per_job_commission; p_other_direct_cost := v_ticket.other_direct_cost;
  if p_customer_charge is null or p_customer_charge < 0 or
     coalesce(p_service_charge,0) < 0 or coalesce(p_discount,0) < 0 or
     coalesce(p_commission,0) < 0 or coalesce(p_other_direct_cost,0) < 0 then
    raise exception 'Repair financial amounts cannot be negative.';
  end if;

  for v_part in select * from public.repair_parts
    where ticket_id = p_ticket_id and state = 'planned' for update
  loop
    if v_part.source_type = 'inventory' then
      update public.inventory set quantity = quantity - v_part.quantity,
        updated_at = now()
      where branch_id = v_ticket.branch_id
        and product_id = v_part.product_id
        and quantity >= v_part.quantity;
      if not found then
        raise exception 'Insufficient repair-part stock.';
      end if;
      v_inventory_cost := v_inventory_cost +
        v_part.quantity * v_part.unit_cost_snapshot;
    else
      v_direct_cost := v_direct_cost +
        v_part.quantity * v_part.unit_cost_snapshot;
      if v_part.settlement_type = 'supplier_payable' then
        insert into public.supplier_ledger_entries(
          tenant_id, branch_id, supplier_id, entry_type, direction, amount,
          source_event_key, reference_type, reference_id, description,
          occurred_at, created_by
        ) values (
          v_ticket.tenant_id, v_ticket.branch_id, v_part.supplier_id,
          'goods_receipt', 'increase',
          v_part.quantity * v_part.unit_cost_snapshot,
          'repair:direct-part:' || v_part.id::text,
          'repair_part', v_part.id, 'Direct repair part', now(), auth.uid()
        ) on conflict (tenant_id,branch_id,source_event_key) do nothing;
        update public.suppliers set outstanding_balance =
          outstanding_balance + v_part.quantity * v_part.unit_cost_snapshot
        where id = v_part.supplier_id;
      end if;
    end if;
    update public.repair_parts set state = 'consumed',
      consumed_at = now(), updated_at = now() where id = v_part.id;
  end loop;

  select coalesce(sum(amount),0) into v_paid
  from public.repair_payments where ticket_id = p_ticket_id;
  if v_paid > p_customer_charge + 0.01 then
    raise exception 'Customer charge cannot be below payments already received.';
  end if;
  v_profit := p_customer_charge - v_inventory_cost - v_direct_cost
    - coalesce(p_commission,0) - coalesce(p_other_direct_cost,0);
  insert into public.repair_financial_events(
    id, tenant_id, branch_id, ticket_id, event_type, source_event_key,
    revenue_amount, inventory_cost, direct_parts_cost, commission_cost,
    other_direct_cost, gross_profit, occurred_at, created_by
  ) values (
    p_event_id, v_ticket.tenant_id, v_ticket.branch_id, p_ticket_id,
    'completion', 'repair:completion:' || p_event_id::text,
    p_customer_charge, v_inventory_cost, v_direct_cost,
    coalesce(p_commission,0), coalesce(p_other_direct_cost,0),
    v_profit, now(), auth.uid()
  );
  update public.repair_tickets set status = 'delivered',
    customer_charge = p_customer_charge, total_cost = p_customer_charge,
    service_charge = coalesce(p_service_charge,0),
    discount_amount = coalesce(p_discount,0),
    parts_cost = v_inventory_cost + v_direct_cost,
    labor_cost = coalesce(p_commission,0),
    per_job_commission = coalesce(p_commission,0),
    other_direct_cost = coalesce(p_other_direct_cost,0),
    delivered_at = now(), finalized_at = now(), updated_at = now()
  where id = p_ticket_id;
  insert into public.repair_status_logs(
    id, ticket_id, tenant_id, branch_id, old_status, new_status,
    changed_by, note
  ) values (
    p_event_id, p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, v_ticket.status,
    'delivered', auth.uid(), 'Repair financial delivery'
  );
  return p_event_id;
end
$function$;

create or replace function public.cancel_repair_ticket_v3(
  p_ticket_id uuid,
  p_event_id uuid,
  p_refund_id uuid,
  p_refund_account_id uuid,
  p_refund_ledger_transaction_id uuid
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $function$
declare
  v_ticket public.repair_tickets%rowtype;
  v_completion public.repair_financial_events%rowtype;
  v_account public.accounts%rowtype;
  v_refund public.repair_payment_refunds%rowtype;
  v_part record;
  v_paid numeric(12,2);
begin
  perform pg_advisory_xact_lock(hashtextextended(p_ticket_id::text, 0));
  select * into v_ticket from public.repair_tickets
  where id = p_ticket_id for update;
  if not found then raise exception 'Repair ticket not found.'; end if;
  if public.current_user_tenant_id() is distinct from v_ticket.tenant_id
     or not public.current_user_has_branch_permission(
       v_ticket.tenant_id, v_ticket.branch_id, 'repair.ticket.update'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;
  if v_ticket.status = 'cancelled' then return p_event_id; end if;

  select coalesce(sum(amount),0) into v_paid
  from public.repair_payments where ticket_id = p_ticket_id;
  select * into v_refund from public.repair_payment_refunds
  where ticket_id = p_ticket_id;

  if v_paid > 0 and v_refund.id is null then
    if p_refund_id is null or p_refund_account_id is null
       or p_refund_ledger_transaction_id is null then
      raise exception using errcode = '22023',
        message = 'Select an account for the customer refund.';
    end if;
    select * into v_account from public.accounts
    where id = p_refund_account_id for update;
    if v_account.id is null
       or v_account.tenant_id <> v_ticket.tenant_id
       or v_account.branch_id <> v_ticket.branch_id
       or not v_account.is_active then
      raise exception using errcode = '22023',
        message = 'Selected refund account is not available.';
    end if;
    if v_account.current_balance + 0.01 < v_paid then
      raise exception using errcode = '23514',
        message = 'Selected account has insufficient refund balance.';
    end if;
    insert into public.account_transactions(
      id, tenant_id, branch_id, account_id, transaction_type, direction,
      amount, description, reference_type, reference_id, source_event_key,
      transaction_at, created_by, created_at
    ) values (
      p_refund_ledger_transaction_id, v_ticket.tenant_id, v_ticket.branch_id,
      p_refund_account_id, 'other', 'out', v_paid,
      'Repair cancellation refund', 'repair_payment_refund',
      p_refund_id::text, 'repair:refund:' || p_ticket_id::text,
      now(), auth.uid(), now()
    );
    insert into public.repair_payment_refunds(
      id, tenant_id, branch_id, ticket_id, account_id, amount,
      ledger_transaction_id, refunded_by, refunded_at
    ) values (
      p_refund_id, v_ticket.tenant_id, v_ticket.branch_id, p_ticket_id,
      p_refund_account_id, v_paid, p_refund_ledger_transaction_id,
      auth.uid(), now()
    );
    update public.accounts set current_balance = current_balance - v_paid,
      updated_at = now() where id = p_refund_account_id;
  elsif v_paid > 0 and (
    v_refund.amount is distinct from v_paid
    or (
      p_refund_account_id is not null
      and v_refund.account_id is distinct from p_refund_account_id
    )
  ) then
    raise exception using errcode = '23505',
      message = 'Repair refund identity conflicts.';
  end if;

  if v_ticket.status in ('completed','delivered') and (
    not v_ticket.delivery_accounting or v_ticket.finalized_at is not null or exists (
      select 1 from public.repair_financial_events where ticket_id = p_ticket_id and event_type = 'completion'
    )
  ) then
    select * into v_completion from public.repair_financial_events
    where ticket_id = p_ticket_id and event_type = 'completion'
    order by occurred_at desc limit 1 for update;
    if not found then raise exception 'Completion snapshot is missing.'; end if;
    for v_part in select * from public.repair_parts
      where ticket_id = p_ticket_id and state = 'consumed' for update
    loop
      if v_part.source_type = 'inventory' then
        insert into public.inventory(branch_id, product_id, quantity, updated_at)
        values (v_ticket.branch_id, v_part.product_id, v_part.quantity, now())
        on conflict (branch_id, product_id) do update set
          quantity = public.inventory.quantity + excluded.quantity,
          updated_at = now();
      end if;
      if v_part.source_type = 'direct_purchase'
         and v_part.settlement_type = 'supplier_payable' then
        if not exists (
          select 1 from public.suppliers where id = v_part.supplier_id
          and outstanding_balance >=
            v_part.quantity * v_part.unit_cost_snapshot
        ) then
          raise exception
            'Resolve paid supplier amount before repair cancellation.';
        end if;
        insert into public.supplier_ledger_entries(
          tenant_id, branch_id, supplier_id, entry_type, direction, amount,
          source_event_key, reference_type, reference_id, description,
          occurred_at, created_by
        ) values (
          v_ticket.tenant_id, v_ticket.branch_id, v_part.supplier_id,
          'credit_note', 'decrease',
          v_part.quantity * v_part.unit_cost_snapshot,
          'repair:direct-part-reversal:' || v_part.id::text,
          'repair_part', v_part.id, 'Cancelled direct repair part',
          now(), auth.uid()
        ) on conflict (tenant_id,branch_id,source_event_key) do nothing;
        update public.suppliers set outstanding_balance =
          outstanding_balance -
            v_part.quantity * v_part.unit_cost_snapshot
        where id = v_part.supplier_id;
      end if;
      update public.repair_parts set state = 'reversed',
        reversed_at = now(), updated_at = now() where id = v_part.id;
    end loop;
    insert into public.repair_financial_events(
      id, tenant_id, branch_id, ticket_id, event_type, source_event_key,
      revenue_amount, inventory_cost, direct_parts_cost, commission_cost,
      other_direct_cost, gross_profit, reversal_of_event_id,
      occurred_at, created_by
    ) values (
      p_event_id, v_ticket.tenant_id, v_ticket.branch_id, p_ticket_id,
      'reversal', 'repair:reversal:' || p_event_id::text,
      -v_completion.revenue_amount, -v_completion.inventory_cost,
      -v_completion.direct_parts_cost, -v_completion.commission_cost,
      -v_completion.other_direct_cost, -v_completion.gross_profit,
      v_completion.id, now(), auth.uid()
    );
  end if;
  update public.repair_tickets set status = 'cancelled',
    reversed_at = case when finalized_at is null then null else now() end,
    updated_at = now() where id = p_ticket_id;
  insert into public.repair_status_logs(
    ticket_id, tenant_id, branch_id, old_status, new_status,
    changed_by, note
  ) values (
    p_ticket_id, v_ticket.tenant_id, v_ticket.branch_id, v_ticket.status,
    'cancelled', auth.uid(), 'Repair cancellation with customer refund'
  );
  return p_event_id;
end
$function$;
revoke all on function public.prepare_repair_ticket_v3(uuid,uuid,numeric,numeric,numeric,numeric,numeric) from public;
grant execute on function public.prepare_repair_ticket_v3(uuid,uuid,numeric,numeric,numeric,numeric,numeric) to authenticated;
revoke all on function public.deliver_repair_ticket_v3(uuid,uuid) from public;
grant execute on function public.deliver_repair_ticket_v3(uuid,uuid) to authenticated;

-- Prevent generic status updates from bypassing the new delivery transaction.
-- RPC-owned posting sets finalized_at together with status under the same lock.
create or replace function public.guard_deferred_repair_delivery() returns trigger
language plpgsql set search_path = public, pg_temp as $guard$
begin
  if current_user in ('authenticated','anon') and (
    new.delivery_accounting is distinct from old.delivery_accounting or
    (old.delivery_accounting and (
      new.finalized_at is distinct from old.finalized_at or
      new.customer_charge is distinct from old.customer_charge or
      new.service_charge is distinct from old.service_charge or
      new.discount_amount is distinct from old.discount_amount or
      new.per_job_commission is distinct from old.per_job_commission or
      new.other_direct_cost is distinct from old.other_direct_cost or
      new.status is distinct from old.status
    ))
  ) then raise exception 'Use the repair financial workflow.'; end if;
  if old.delivery_accounting and new.status = 'delivered' and old.status <> 'delivered'
    and new.finalized_at is null and not exists (
      select 1 from public.repair_financial_events where ticket_id = old.id and event_type = 'completion'
    ) then raise exception 'Use the repair delivery workflow.'; end if;
  return new;
end $guard$;
drop trigger if exists guard_deferred_repair_delivery on public.repair_tickets;
create trigger guard_deferred_repair_delivery before update on public.repair_tickets
for each row execute function public.guard_deferred_repair_delivery();
revoke all on function public.guard_deferred_repair_delivery() from public;
create or replace function public.validate_repair_customer_shop() returns trigger
language plpgsql set search_path = public, pg_temp as $customer$
begin
  if new.customer_id is not null and not exists (
    select 1 from public.customers where id = new.customer_id and tenant_id = new.tenant_id
  ) then raise exception using errcode = '23514', message = 'Repair customer must belong to the same shop.'; end if;
  return new;
end $customer$;
drop trigger if exists validate_repair_customer_shop on public.repair_tickets;
create trigger validate_repair_customer_shop before insert or update of customer_id,tenant_id
on public.repair_tickets for each row execute function public.validate_repair_customer_shop();
revoke all on function public.validate_repair_customer_shop() from public;
commit;
