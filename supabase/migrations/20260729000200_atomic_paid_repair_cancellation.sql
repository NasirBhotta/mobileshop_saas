-- Atomically refund a paid repair and reverse every completion-side financial
-- and stock effect. Stable IDs make offline retries idempotent.
create table if not exists public.repair_payment_refunds (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  ticket_id uuid not null unique
    references public.repair_tickets(id) on delete restrict,
  account_id uuid not null references public.accounts(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  ledger_transaction_id uuid not null unique
    references public.account_transactions(id) on delete restrict,
  refunded_by uuid not null references public.users(id),
  refunded_at timestamptz not null default now()
);

alter table public.repair_payment_refunds enable row level security;
drop policy if exists "tenant users can read repair payment refunds"
  on public.repair_payment_refunds;
create policy "tenant users can read repair payment refunds"
on public.repair_payment_refunds for select to authenticated
using (
  public.current_user_has_branch_permission(
    tenant_id, branch_id, 'repair.ticket.view'
  )
);

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
  if public.current_user_tenant_id() <> v_ticket.tenant_id
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

  if v_ticket.status in ('completed','delivered') then
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

revoke all on function public.cancel_repair_ticket_v3(
  uuid,uuid,uuid,uuid,uuid
) from public, anon;
grant execute on function public.cancel_repair_ticket_v3(
  uuid,uuid,uuid,uuid,uuid
) to authenticated, service_role;
