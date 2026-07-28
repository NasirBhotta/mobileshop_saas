-- Add supplier statement history and explicit PO product-resolution states.
-- Existing rows remain linked to their current products.

alter table public.purchase_order_items
  alter column product_id drop not null,
  add column if not exists product_resolution text
    not null default 'existing_product',
  add column if not exists product_draft jsonb,
  add column if not exists resolved_product_id uuid;

alter table public.goods_receipt_items
  alter column product_id drop not null,
  add column if not exists item_resolution text
    not null default 'existing_product',
  add column if not exists item_name text;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'po_items_product_resolution_check'
      and conrelid = 'public.purchase_order_items'::regclass
  ) then
    alter table public.purchase_order_items
      add constraint po_items_product_resolution_check
      check (
        product_resolution in (
          'existing_product', 'create_on_receipt',
          'resolve_on_receipt', 'direct_use'
        )
      ) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'po_items_resolution_link_check'
      and conrelid = 'public.purchase_order_items'::regclass
  ) then
    alter table public.purchase_order_items
      add constraint po_items_resolution_link_check
      check (
        product_resolution <> 'existing_product' or product_id is not null
      ) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'po_items_resolved_product_id_fkey'
      and conrelid = 'public.purchase_order_items'::regclass
  ) then
    alter table public.purchase_order_items
      add constraint po_items_resolved_product_id_fkey
      foreign key (resolved_product_id) references public.products(id)
      on delete restrict not valid;
  end if;
end
$block$;

create table if not exists public.supplier_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  entry_type text not null check (
    entry_type in (
      'opening_balance', 'goods_receipt', 'supplier_payment',
      'purchase_return', 'credit_note', 'payment_reversal', 'adjustment'
    )
  ),
  direction text not null check (direction in ('increase', 'decrease')),
  amount numeric(12, 2) not null check (amount > 0),
  source_event_key text not null,
  reference_type text not null,
  reference_id uuid not null,
  description text,
  occurred_at timestamptz not null,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, branch_id, source_event_key)
);

create index if not exists idx_supplier_ledger_statement
  on public.supplier_ledger_entries(
    supplier_id, occurred_at, created_at, id
  );

alter table public.supplier_ledger_entries enable row level security;
drop policy if exists "branch users can read supplier ledger"
  on public.supplier_ledger_entries;
create policy "branch users can read supplier ledger"
on public.supplier_ledger_entries for select to authenticated
using (
  public.current_user_has_branch_permission(
    tenant_id, branch_id, 'supplier.supplier.view'
  )
);

create or replace function public.capture_supplier_source_ledger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if tg_table_name = 'goods_receipts' then
    if new.total_received_value <= 0 then
      return new;
    end if;
    insert into public.supplier_ledger_entries (
      tenant_id, branch_id, supplier_id, entry_type, direction, amount,
      source_event_key, reference_type, reference_id, description,
      occurred_at, created_by
    ) values (
      new.tenant_id, new.branch_id, new.supplier_id, 'goods_receipt',
      'increase', new.total_received_value,
      'supplier:receipt:' || new.id::text, 'goods_receipt', new.id,
      'Goods receipt ' || new.receipt_no, new.received_at, new.received_by
    )
    on conflict (tenant_id, branch_id, source_event_key) do nothing;
    if exists (
      select 1
      from public.supplier_ledger_entries entry
      where entry.tenant_id = new.tenant_id
        and entry.branch_id = new.branch_id
        and entry.source_event_key = 'supplier:receipt:' || new.id::text
        and (
          entry.amount is distinct from new.total_received_value
          or entry.supplier_id is distinct from new.supplier_id
        )
    ) then
      raise exception using errcode = '23505',
        message = 'Goods receipt supplier ledger identity conflicts.';
    end if;
  elsif tg_table_name = 'supplier_payments' then
    insert into public.supplier_ledger_entries (
      tenant_id, branch_id, supplier_id, entry_type, direction, amount,
      source_event_key, reference_type, reference_id, description,
      occurred_at, created_by
    ) values (
      new.tenant_id, new.branch_id, new.supplier_id, 'supplier_payment',
      'decrease', new.amount, 'supplier:payment:' || new.id::text,
      'supplier_payment', new.id, 'Supplier payment',
      new.paid_at, new.paid_by
    )
    on conflict (tenant_id, branch_id, source_event_key) do nothing;
  end if;
  return new;
end
$function$;

drop trigger if exists capture_goods_receipt_supplier_ledger
  on public.goods_receipts;
create trigger capture_goods_receipt_supplier_ledger
after insert or update of total_received_value on public.goods_receipts
for each row execute function public.capture_supplier_source_ledger();

drop trigger if exists capture_supplier_payment_ledger
  on public.supplier_payments;
create trigger capture_supplier_payment_ledger
after insert on public.supplier_payments
for each row execute function public.capture_supplier_source_ledger();

revoke all on table public.supplier_ledger_entries from anon;
grant select on table public.supplier_ledger_entries to authenticated;
